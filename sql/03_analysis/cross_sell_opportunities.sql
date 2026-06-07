-- =============================================================================
-- FILE: 03_analysis/cross_sell_opportunities.sql
-- DESC: Identify customers eligible for product cross-sell
--       Priority: current account holders without savings / credit card / mortgage
--       Used to feed relationship manager outreach lists
-- =============================================================================

WITH
-- All active product holdings per customer
product_holdings AS (
  SELECT
    a.customer_id,
    STRING_AGG(DISTINCT p.product_type ORDER BY p.product_type) AS held_products,
    COUNTIF(p.product_type = 'Current Account') > 0   AS has_current_account,
    COUNTIF(p.product_type = 'Savings') > 0           AS has_savings,
    COUNTIF(p.product_type = 'Credit Card') > 0       AS has_credit_card,
    COUNTIF(p.product_type = 'Mortgage') > 0          AS has_mortgage,
    COUNTIF(p.product_type = 'Loan') > 0              AS has_loan,
    COUNT(DISTINCT p.product_type)                    AS product_count,
    SUM(ABS(a.balance_gbp))                           AS total_balance_gbp
  FROM `retail_banking.fact_accounts` a
  JOIN `retail_banking.dim_products` p ON a.product_id = p.product_id
  WHERE
    a.account_status = 'Active'
    AND a.snapshot_month = DATE_TRUNC(CURRENT_DATE(), MONTH)
  GROUP BY a.customer_id
),

-- Transaction behaviour signals (last 6 months)
behaviour AS (
  SELECT
    customer_id,
    SUM(amount_gbp)                                               AS total_spend_6m,
    AVG(amount_gbp)                                               AS avg_txn_amount,
    COUNTIF(transaction_category = 'Mortgage/Rent')               AS rent_payments,
    COUNTIF(transaction_category IN ('International', 'FX'))      AS intl_transactions,
    COUNTIF(merchant_country != 'GB')                             AS foreign_txns,
    COUNT(*)                                                      AS total_txns
  FROM `retail_banking.fact_transactions`
  WHERE transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
    AND transaction_type = 'Debit'
    AND is_flagged = FALSE
  GROUP BY customer_id
),

-- Enrich with customer profile
enriched AS (
  SELECT
    c.customer_id,
    c.customer_segment,
    c.age_band,
    c.region,
    c.risk_rating,
    c.tenure_years,
    ph.product_count,
    ph.total_balance_gbp,
    ph.has_current_account,
    ph.has_savings,
    ph.has_credit_card,
    ph.has_mortgage,
    ph.has_loan,
    b.total_spend_6m,
    b.avg_txn_amount,
    b.rent_payments,
    b.intl_transactions
  FROM `retail_banking.dim_customers` c
  JOIN product_holdings ph ON c.customer_id = ph.customer_id
  LEFT JOIN behaviour b ON c.customer_id = b.customer_id
  WHERE
    c.kyc_status = 'Verified'
    AND c.risk_rating IN ('Low', 'Medium')  -- exclude high-risk from proactive outreach
    AND ph.has_current_account = TRUE        -- must be primary banked customer
),

-- Score each cross-sell opportunity
opportunities AS (
  SELECT
    *,

    -- SAVINGS propensity: high balance, no savings product, not student
    CASE
      WHEN has_savings = FALSE
        AND total_balance_gbp > 2000
        AND customer_segment IN ('Premier', 'Retail')
        THEN TRUE
      ELSE FALSE
    END AS opportunity_savings,

    -- CREDIT CARD propensity: regular spender, no card, decent tenure
    CASE
      WHEN has_credit_card = FALSE
        AND total_spend_6m > 1500
        AND tenure_years >= 1
        AND age_band NOT IN ('18-24')
        AND risk_rating = 'Low'
        THEN TRUE
      ELSE FALSE
    END AS opportunity_credit_card,

    -- MORTGAGE propensity: renting, right age band, Premier segment
    CASE
      WHEN has_mortgage = FALSE
        AND rent_payments >= 4   -- regular rent outgoing
        AND age_band IN ('25-34', '35-44')
        AND customer_segment IN ('Premier', 'Private')
        AND total_balance_gbp > 10000
        THEN TRUE
      ELSE FALSE
    END AS opportunity_mortgage,

    -- TRAVEL / INTERNATIONAL CARD: frequent international transactions
    CASE
      WHEN intl_transactions > 10
        AND has_credit_card = FALSE
        THEN TRUE
      ELSE FALSE
    END AS opportunity_travel_card

  FROM enriched
)

-- Final prioritised output
SELECT
  customer_id,
  customer_segment,
  region,
  age_band,
  risk_rating,
  product_count,
  ROUND(total_balance_gbp, 0)   AS total_balance_gbp,
  ROUND(total_spend_6m, 0)      AS total_spend_6m,

  -- Which products to pitch
  opportunity_savings,
  opportunity_credit_card,
  opportunity_mortgage,
  opportunity_travel_card,

  -- Total opportunities per customer (priority scoring)
  (
    CAST(opportunity_savings       AS INT64) +
    CAST(opportunity_credit_card   AS INT64) +
    CAST(opportunity_mortgage      AS INT64) +
    CAST(opportunity_travel_card   AS INT64)
  )                                                   AS opportunity_count,

  -- Recommended next best product
  CASE
    WHEN opportunity_mortgage     THEN 'Residential Mortgage'
    WHEN opportunity_credit_card  THEN 'Cashback Credit Card'
    WHEN opportunity_savings      THEN 'Fixed Rate Bond 12M'
    WHEN opportunity_travel_card  THEN 'Platinum Credit Card'
    ELSE 'None'
  END AS recommended_product

FROM opportunities
WHERE (
  opportunity_savings OR opportunity_credit_card
  OR opportunity_mortgage OR opportunity_travel_card
)
ORDER BY opportunity_count DESC, total_balance_gbp DESC;
