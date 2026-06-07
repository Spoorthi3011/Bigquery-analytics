-- =============================================================================
-- FILE: 05_reporting/monthly_pnl.sql
-- DESC: Monthly profit & loss summary by product and region
--       Scheduled to run on 1st of each month via BigQuery Scheduled Queries
--       Output feeds Looker Studio executive dashboard
-- =============================================================================

DECLARE report_month DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH);

-- =============================================================================
-- MAIN P&L VIEW — Product × Region × Month
-- =============================================================================
CREATE OR REPLACE VIEW `retail_banking.v_monthly_pnl` AS

WITH
-- Net Interest Income: interest earned on lending products
net_interest_income AS (
  SELECT
    a.snapshot_month,
    p.product_type,
    p.product_family,
    c.region,
    c.customer_segment,
    SUM(a.interest_charged_gbp)     AS interest_income_gbp,   -- lending income
    SUM(a.interest_earned_gbp)      AS interest_cost_gbp,     -- deposit cost
    SUM(a.interest_charged_gbp)
      - SUM(a.interest_earned_gbp)  AS net_interest_gbp
  FROM `retail_banking.fact_accounts` a
  JOIN `retail_banking.dim_products`  p ON a.product_id = p.product_id
  JOIN `retail_banking.dim_customers` c ON a.customer_id = c.customer_id
  GROUP BY 1, 2, 3, 4, 5
),

-- Fee Income: monthly account fees + transaction fees
fee_income AS (
  SELECT
    DATE_TRUNC(t.transaction_date, MONTH) AS snapshot_month,
    p.product_type,
    p.product_family,
    c.region,
    c.customer_segment,
    SUM(a.fees_charged_gbp)               AS fee_income_gbp
  FROM `retail_banking.fact_accounts` a
  JOIN `retail_banking.dim_products`  p ON a.product_id = p.product_id
  JOIN `retail_banking.dim_customers` c ON a.customer_id = c.customer_id
  JOIN `retail_banking.fact_transactions` t ON a.customer_id = t.customer_id
  WHERE t.transaction_date BETWEEN a.snapshot_month
                               AND LAST_DAY(a.snapshot_month)
  GROUP BY 1, 2, 3, 4, 5
),

-- Account counts for averages
account_counts AS (
  SELECT
    a.snapshot_month,
    p.product_type,
    c.region,
    c.customer_segment,
    COUNT(DISTINCT a.account_id)            AS active_accounts,
    COUNT(DISTINCT a.customer_id)           AS active_customers,
    SUM(CASE WHEN a.days_in_arrears > 0 THEN 1 ELSE 0 END) AS accounts_in_arrears,
    AVG(a.balance_gbp)                      AS avg_balance_gbp,
    SUM(ABS(a.balance_gbp))                 AS total_book_gbp
  FROM `retail_banking.fact_accounts` a
  JOIN `retail_banking.dim_products`  p ON a.product_id = p.product_id
  JOIN `retail_banking.dim_customers` c ON a.customer_id = c.customer_id
  WHERE a.account_status = 'Active'
  GROUP BY 1, 2, 3, 4
)

SELECT
  nii.snapshot_month,
  nii.product_type,
  nii.product_family,
  nii.region,
  nii.customer_segment,

  -- Volume metrics
  ac.active_accounts,
  ac.active_customers,
  ROUND(ac.total_book_gbp, 0)               AS total_book_gbp,
  ROUND(ac.avg_balance_gbp, 2)              AS avg_balance_gbp,

  -- Income metrics
  ROUND(nii.net_interest_gbp, 0)            AS net_interest_income_gbp,
  ROUND(nii.interest_income_gbp, 0)         AS gross_interest_income_gbp,
  ROUND(nii.interest_cost_gbp, 0)           AS interest_cost_gbp,
  ROUND(COALESCE(fi.fee_income_gbp, 0), 0)  AS fee_income_gbp,
  ROUND(
    nii.net_interest_gbp + COALESCE(fi.fee_income_gbp, 0),
    0
  )                                         AS total_revenue_gbp,

  -- Efficiency metrics
  ac.accounts_in_arrears,
  ROUND(
    SAFE_DIVIDE(ac.accounts_in_arrears, ac.active_accounts) * 100,
    2
  )                                         AS arrears_rate_pct,

  -- Net Interest Margin (annualised)
  ROUND(
    SAFE_DIVIDE(nii.net_interest_gbp * 12, NULLIF(ac.total_book_gbp, 0)) * 100,
    3
  )                                         AS nim_annualised_pct,

  -- Month-over-month revenue change
  ROUND(
    nii.net_interest_gbp + COALESCE(fi.fee_income_gbp, 0)
    - LAG(nii.net_interest_gbp + COALESCE(fi.fee_income_gbp, 0)) OVER (
        PARTITION BY nii.product_type, nii.region, nii.customer_segment
        ORDER BY nii.snapshot_month
      ),
    0
  )                                         AS mom_revenue_delta_gbp,

  CURRENT_TIMESTAMP()                       AS refreshed_at

FROM net_interest_income nii
LEFT JOIN fee_income fi
  ON  nii.snapshot_month    = fi.snapshot_month
  AND nii.product_type      = fi.product_type
  AND nii.region            = fi.region
  AND nii.customer_segment  = fi.customer_segment
LEFT JOIN account_counts ac
  ON  nii.snapshot_month    = ac.snapshot_month
  AND nii.product_type      = ac.product_type
  AND nii.region            = ac.region
  AND nii.customer_segment  = ac.customer_segment
ORDER BY nii.snapshot_month DESC, total_revenue_gbp DESC;


-- =============================================================================
-- SCHEDULED QUERY: Monthly executive summary (parameterised)
-- Set up in BigQuery UI: Scheduled Queries → @run_time parameter
-- =============================================================================

/*
-- Snapshot top-level KPIs for the prior month into a summary table
INSERT INTO `retail_banking.monthly_executive_summary`
SELECT
  @run_date                                             AS report_month,
  SUM(total_revenue_gbp)                                AS total_revenue_gbp,
  SUM(net_interest_income_gbp)                          AS total_nii_gbp,
  SUM(fee_income_gbp)                                   AS total_fee_income_gbp,
  SUM(active_customers)                                 AS total_active_customers,
  SUM(active_accounts)                                  AS total_active_accounts,
  SUM(total_book_gbp)                                   AS total_book_gbp,
  AVG(nim_annualised_pct)                               AS avg_nim_pct,
  AVG(arrears_rate_pct)                                 AS avg_arrears_rate_pct,
  CURRENT_TIMESTAMP()                                   AS inserted_at
FROM `retail_banking.v_monthly_pnl`
WHERE snapshot_month = DATE_TRUNC(@run_date, MONTH);
*/
