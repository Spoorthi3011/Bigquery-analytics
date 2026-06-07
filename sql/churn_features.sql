-- =============================================================================
-- FILE: 03_analysis/churn_features.sql
-- DESC: Feature engineering for customer churn prediction
--       Output feeds BigQuery ML logistic regression model (bqml_churn.sql)
--       Label: customer closes all accounts within 90 days (binary)
-- =============================================================================

-- =============================================================================
-- FEATURE TABLE — one row per customer, trailing 6 months of signals
-- =============================================================================
CREATE OR REPLACE TABLE `retail_banking.ml_churn_features` AS

WITH
-- Define churn label: closed all accounts in next 90 days
churn_labels AS (
  SELECT
    a.customer_id,
    MAX(
      CASE
        WHEN a.account_status = 'Closed'
          AND a.closed_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY)
          THEN 1
        ELSE 0
      END
    ) AS churned
  FROM `retail_banking.fact_accounts` a
  GROUP BY a.customer_id
),

-- Transaction behaviour (last 6 months)
txn_features AS (
  SELECT
    customer_id,
    COUNT(*)                                                          AS txn_count_6m,
    SUM(amount_gbp)                                                   AS total_spend_6m,
    AVG(amount_gbp)                                                   AS avg_txn_amount_6m,
    STDDEV(amount_gbp)                                                AS stddev_txn_amount,
    COUNT(DISTINCT transaction_category)                              AS unique_categories,
    COUNT(DISTINCT merchant_name)                                     AS unique_merchants,
    COUNT(DISTINCT DATE_TRUNC(transaction_date, MONTH))               AS active_months,
    COUNTIF(channel = 'Mobile')                                       AS mobile_txns,
    COUNTIF(channel = 'Branch')                                       AS branch_txns,
    COUNTIF(channel = 'ATM')                                         AS atm_txns,
    COUNTIF(is_international = TRUE)                                  AS intl_txns,

    -- Recency
    DATE_DIFF(CURRENT_DATE(), MAX(transaction_date), DAY)             AS days_since_last_txn,

    -- Trend: compare last 3m vs prior 3m spend
    SUM(CASE WHEN transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
             THEN amount_gbp ELSE 0 END)                              AS spend_last_3m,
    SUM(CASE WHEN transaction_date < DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
             THEN amount_gbp ELSE 0 END)                              AS spend_prior_3m
  FROM `retail_banking.fact_transactions`
  WHERE
    transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
    AND transaction_type = 'Debit'
    AND is_flagged = FALSE
  GROUP BY customer_id
),

-- Account health signals
account_features AS (
  SELECT
    a.customer_id,
    COUNT(DISTINCT a.account_id)                                      AS product_count,
    AVG(a.utilisation_pct)                                            AS avg_credit_utilisation,
    MAX(a.days_in_arrears)                                            AS max_days_in_arrears,
    SUM(a.missed_payments_3m)                                         AS total_missed_payments_3m,
    SUM(a.fees_charged_gbp)                                           AS total_fees_charged_6m,
    AVG(a.balance_gbp)                                                AS avg_balance,
    COUNTIF(a.account_status = 'Overdrawn')                           AS overdrawn_accounts,
    COUNTIF(a.account_status = 'Dormant')                             AS dormant_accounts
  FROM `retail_banking.fact_accounts` a
  WHERE a.snapshot_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
    AND a.account_status != 'Closed'
  GROUP BY a.customer_id
)

-- Combine all features
SELECT
  c.customer_id,

  -- Demographics
  DATE_DIFF(CURRENT_DATE(), c.date_of_birth, YEAR)    AS age,
  DATE_DIFF(CURRENT_DATE(), c.customer_since, YEAR)   AS tenure_years,
  c.customer_segment,
  c.region,
  c.risk_rating,

  -- Transaction features
  COALESCE(t.txn_count_6m, 0)             AS txn_count_6m,
  COALESCE(t.total_spend_6m, 0)           AS total_spend_6m,
  COALESCE(t.avg_txn_amount_6m, 0)        AS avg_txn_amount_6m,
  COALESCE(t.unique_categories, 0)        AS unique_categories,
  COALESCE(t.unique_merchants, 0)         AS unique_merchants,
  COALESCE(t.active_months, 0)            AS active_months_6m,
  COALESCE(t.days_since_last_txn, 999)    AS days_since_last_txn,
  COALESCE(t.mobile_txns, 0)             AS mobile_txns,
  COALESCE(t.branch_txns, 0)             AS branch_txns,
  COALESCE(t.intl_txns, 0)              AS intl_txns,

  -- Spend trend (negative = declining engagement)
  COALESCE(
    SAFE_DIVIDE(t.spend_last_3m - t.spend_prior_3m, NULLIF(t.spend_prior_3m, 0)),
    0
  )                                       AS spend_trend_pct,

  -- Account health
  COALESCE(af.product_count, 0)           AS product_count,
  COALESCE(af.avg_credit_utilisation, 0)  AS avg_credit_utilisation,
  COALESCE(af.max_days_in_arrears, 0)     AS max_days_in_arrears,
  COALESCE(af.total_missed_payments_3m,0) AS total_missed_payments_3m,
  COALESCE(af.total_fees_charged_6m, 0)   AS total_fees_charged_6m,
  COALESCE(af.avg_balance, 0)             AS avg_balance,
  COALESCE(af.overdrawn_accounts, 0)      AS overdrawn_accounts,
  COALESCE(af.dormant_accounts, 0)        AS dormant_accounts,

  -- NPS as signal
  c.nps_score,

  -- TARGET LABEL
  COALESCE(cl.churned, 0)                 AS churned,

  CURRENT_TIMESTAMP()                     AS feature_date

FROM `retail_banking.dim_customers` c
LEFT JOIN txn_features t       ON c.customer_id = t.customer_id
LEFT JOIN account_features af  ON c.customer_id = af.customer_id
LEFT JOIN churn_labels cl      ON c.customer_id = cl.customer_id
WHERE c.kyc_status = 'Verified';
