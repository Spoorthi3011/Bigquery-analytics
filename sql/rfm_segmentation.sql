-- =============================================================================
-- FILE: 03_analysis/rfm_segmentation.sql
-- DESC: Customer RFM (Recency, Frequency, Monetary) segmentation
--       Industry-standard method for customer value classification
-- OUTPUT: retail_banking.customer_rfm_segments (materialised view)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Compute raw RFM metrics per customer
-- Reference window: rolling 12 months from most recent transaction
-- -----------------------------------------------------------------------------
WITH
date_spine AS (
  -- Anchor date — parameterise for scheduled runs
  SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY) AS analysis_date
),

raw_rfm AS (
  SELECT
    t.customer_id,
    -- Recency: days since last transaction (lower = more recent = better)
    DATE_DIFF(
      (SELECT analysis_date FROM date_spine),
      MAX(t.transaction_date),
      DAY
    )                                                           AS recency_days,

    -- Frequency: distinct active months in the last 12 months
    COUNT(DISTINCT FORMAT_DATE('%Y-%m', t.transaction_date))    AS frequency_months,

    -- Monetary: total debit spend in the last 12 months (£)
    ROUND(
      SUM(CASE WHEN t.transaction_type = 'Debit' THEN t.amount_gbp ELSE 0 END),
      2
    )                                                           AS monetary_gbp,

    -- Supporting metrics
    COUNT(*)                                                    AS total_transactions,
    COUNT(DISTINCT t.merchant_name)                             AS unique_merchants,
    MAX(t.transaction_date)                                     AS last_transaction_date,
    MIN(t.transaction_date)                                     AS first_transaction_date

  FROM `retail_banking.fact_transactions` t
  WHERE
    t.transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    AND t.is_flagged = FALSE   -- exclude flagged transactions from CLV calc
  GROUP BY t.customer_id
),

-- -----------------------------------------------------------------------------
-- STEP 2: Score each metric 1-5 using NTILE quintiles
-- -----------------------------------------------------------------------------
scored_rfm AS (
  SELECT
    *,
    -- Recency: reverse score (lower recency days = higher score)
    6 - NTILE(5) OVER (ORDER BY recency_days ASC)   AS r_score,
    NTILE(5) OVER (ORDER BY frequency_months ASC)   AS f_score,
    NTILE(5) OVER (ORDER BY monetary_gbp ASC)       AS m_score
  FROM raw_rfm
),

-- -----------------------------------------------------------------------------
-- STEP 3: Composite score & segment labelling
-- -----------------------------------------------------------------------------
labelled AS (
  SELECT
    *,
    ROUND((r_score + f_score + m_score) / 3.0, 2)  AS rfm_composite_score,

    CASE
      -- Champions: bought recently, buy often, spend the most
      WHEN r_score = 5 AND f_score >= 4 AND m_score >= 4
        THEN 'Champions'

      -- Loyal Customers: buy regularly, decent spend
      WHEN f_score >= 4 AND m_score >= 3
        THEN 'Loyal Customers'

      -- Potential Loyalists: recent, but low frequency
      WHEN r_score >= 4 AND f_score BETWEEN 2 AND 3
        THEN 'Potential Loyalists'

      -- New Customers: high recency, very low frequency
      WHEN r_score = 5 AND f_score = 1
        THEN 'New Customers'

      -- Promising: recent, not frequent yet
      WHEN r_score = 4 AND f_score = 1
        THEN 'Promising'

      -- Need Attention: above average, but fading
      WHEN r_score = 3 AND f_score >= 3 AND m_score >= 3
        THEN 'Need Attention'

      -- About To Sleep: below average recency & frequency
      WHEN r_score BETWEEN 2 AND 3 AND f_score BETWEEN 1 AND 2
        THEN 'About To Sleep'

      -- At Risk: bought often & spent a lot but haven't returned
      WHEN r_score BETWEEN 1 AND 2 AND f_score >= 3 AND m_score >= 3
        THEN 'At Risk'

      -- Can''t Lose Them: made big purchases, not seen recently
      WHEN r_score = 1 AND f_score >= 4 AND m_score >= 4
        THEN 'Cannot Lose Them'

      -- Hibernating: low across all metrics
      WHEN r_score BETWEEN 1 AND 2 AND f_score BETWEEN 1 AND 2
        THEN 'Hibernating'

      ELSE 'Others'
    END AS rfm_segment
  FROM scored_rfm
)

-- -----------------------------------------------------------------------------
-- STEP 4: Final output — join customer attributes for context
-- -----------------------------------------------------------------------------
SELECT
  l.*,
  c.customer_segment,
  c.region,
  c.age_band,
  c.risk_rating,
  c.customer_since,
  DATE_DIFF(CURRENT_DATE(), c.customer_since, YEAR) AS tenure_years,

  -- Estimated CLV tier based on composite score
  CASE
    WHEN l.rfm_composite_score >= 4.0 THEN 'High Value'
    WHEN l.rfm_composite_score >= 2.5 THEN 'Mid Value'
    ELSE 'Low Value'
  END AS clv_tier,

  -- Churn risk proxy (inverse of composite)
  CASE
    WHEN l.r_score <= 2 AND l.f_score <= 2 THEN 'High'
    WHEN l.r_score <= 3 THEN 'Medium'
    ELSE 'Low'
  END AS churn_risk,

  CURRENT_TIMESTAMP() AS computed_at

FROM labelled l
LEFT JOIN `retail_banking.dim_customers` c
  ON l.customer_id = c.customer_id
ORDER BY l.rfm_composite_score DESC;

-- =============================================================================
-- MATERIALISE AS VIEW for dashboard consumption
-- =============================================================================
/*
CREATE OR REPLACE MATERIALIZED VIEW `retail_banking.mv_customer_rfm`
OPTIONS (enable_refresh = true, refresh_interval_minutes = 1440)
AS
  [paste above query here]
*/
