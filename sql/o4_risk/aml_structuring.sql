-- =============================================================================
-- FILE: 04_risk/aml_structuring.sql
-- DESC: Anti-Money Laundering (AML) pattern detection
--       Covers: structuring, round-amount patterns, velocity checks,
--               layering detection, and high-risk country exposure
-- IMPORTANT: This is a portfolio demonstration. Real AML models require
--            regulatory input, STR processes, and compliance sign-off.
-- =============================================================================

-- =============================================================================
-- QUERY 1: STRUCTURING DETECTION
-- Pattern: Multiple transactions just below £10,000 (UK reporting threshold)
-- Classic smurfing / structuring indicator
-- =============================================================================
CREATE OR REPLACE VIEW `retail_banking.aml_structuring_alerts` AS
WITH
daily_sub_threshold AS (
  SELECT
    customer_id,
    transaction_date,
    COUNT(*)                    AS txn_count,
    SUM(amount_gbp)             AS daily_total_gbp,
    MAX(amount_gbp)             AS largest_txn_gbp,
    MIN(amount_gbp)             AS smallest_txn_gbp,
    ARRAY_AGG(transaction_id)   AS transaction_ids
  FROM `retail_banking.fact_transactions`
  WHERE
    amount_gbp BETWEEN 7500 AND 9999   -- just below £10k threshold
    AND transaction_type = 'Credit'    -- incoming funds
  GROUP BY customer_id, transaction_date
),

rolling_7d AS (
  SELECT
    d.*,
    SUM(d.daily_total_gbp) OVER (
      PARTITION BY d.customer_id
      ORDER BY d.transaction_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                           AS rolling_7d_total_gbp,
    SUM(d.txn_count) OVER (
      PARTITION BY d.customer_id
      ORDER BY d.transaction_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                           AS rolling_7d_txn_count
  FROM daily_sub_threshold d
)

SELECT
  r.customer_id,
  c.customer_segment,
  c.risk_rating,
  c.region,
  r.transaction_date,
  r.txn_count,
  ROUND(r.daily_total_gbp, 2)         AS daily_total_gbp,
  ROUND(r.rolling_7d_total_gbp, 2)    AS rolling_7d_total_gbp,
  r.rolling_7d_txn_count,

  -- Risk score (higher = more suspicious)
  CASE
    WHEN r.rolling_7d_txn_count >= 5 AND r.rolling_7d_total_gbp > 40000 THEN 'Critical'
    WHEN r.rolling_7d_txn_count >= 3 AND r.rolling_7d_total_gbp > 25000 THEN 'High'
    WHEN r.rolling_7d_txn_count >= 2 AND r.rolling_7d_total_gbp > 15000 THEN 'Medium'
    ELSE 'Low'
  END AS alert_severity,

  'Structuring - Sub-threshold credits' AS alert_type,
  CURRENT_TIMESTAMP()                   AS detected_at

FROM rolling_7d r
JOIN `retail_banking.dim_customers` c ON r.customer_id = c.customer_id
WHERE
  r.rolling_7d_txn_count >= 2        -- at least 2 such transactions in 7 days
  AND r.rolling_7d_total_gbp > 10000 -- combined > £10k
ORDER BY alert_severity, rolling_7d_total_gbp DESC;


-- =============================================================================
-- QUERY 2: VELOCITY CHECK — Unusual spending spike
-- Pattern: Customer spends significantly more than their 90-day average
-- in a single day (potential account takeover or mule account)
-- =============================================================================
CREATE OR REPLACE VIEW `retail_banking.aml_velocity_alerts` AS
WITH
customer_baseline AS (
  SELECT
    customer_id,
    AVG(daily_spend)                        AS avg_daily_spend,
    STDDEV(daily_spend)                     AS stddev_daily_spend,
    APPROX_QUANTILES(daily_spend, 100)[OFFSET(75)] AS p75_daily_spend,
    APPROX_QUANTILES(daily_spend, 100)[OFFSET(95)] AS p95_daily_spend
  FROM (
    SELECT
      customer_id,
      transaction_date,
      SUM(amount_gbp) AS daily_spend
    FROM `retail_banking.fact_transactions`
    WHERE
      transaction_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                           AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY)
      AND transaction_type = 'Debit'
    GROUP BY customer_id, transaction_date
  )
  GROUP BY customer_id
),

recent_activity AS (
  SELECT
    customer_id,
    transaction_date,
    SUM(amount_gbp)   AS daily_spend,
    COUNT(*)          AS txn_count
  FROM `retail_banking.fact_transactions`
  WHERE
    transaction_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
                         AND CURRENT_DATE()
    AND transaction_type = 'Debit'
  GROUP BY customer_id, transaction_date
)

SELECT
  ra.customer_id,
  ra.transaction_date,
  ROUND(ra.daily_spend, 2)                    AS todays_spend_gbp,
  ROUND(b.avg_daily_spend, 2)                 AS avg_daily_spend_gbp,
  ROUND(b.p95_daily_spend, 2)                 AS p95_daily_spend_gbp,
  ra.txn_count,
  ROUND(
    SAFE_DIVIDE(ra.daily_spend - b.avg_daily_spend, b.stddev_daily_spend),
    2
  )                                           AS z_score,
  ROUND(
    SAFE_DIVIDE(ra.daily_spend, NULLIF(b.avg_daily_spend, 0)),
    1
  )                                           AS spend_multiplier,
  CASE
    WHEN SAFE_DIVIDE(ra.daily_spend, b.avg_daily_spend) > 10 THEN 'Critical'
    WHEN SAFE_DIVIDE(ra.daily_spend, b.avg_daily_spend) > 5  THEN 'High'
    WHEN SAFE_DIVIDE(ra.daily_spend, b.avg_daily_spend) > 3  THEN 'Medium'
    ELSE 'Low'
  END AS alert_severity,
  'Velocity - Unusual daily spend spike' AS alert_type,
  CURRENT_TIMESTAMP()                    AS detected_at
FROM recent_activity ra
JOIN customer_baseline b ON ra.customer_id = b.customer_id
WHERE
  ra.daily_spend > b.p95_daily_spend     -- above customer's own 95th percentile
  AND ra.daily_spend > b.avg_daily_spend * 3  -- at least 3x their average
  AND b.avg_daily_spend > 0
ORDER BY spend_multiplier DESC;


-- =============================================================================
-- QUERY 3: ROUND-AMOUNT PATTERN
-- Pattern: Repeated exact round-number transactions (e.g. £500, £1000, £5000)
-- Indicator of cash layering or structured payments
-- =============================================================================
CREATE OR REPLACE VIEW `retail_banking.aml_round_amount_alerts` AS
SELECT
  customer_id,
  amount_gbp,
  COUNT(*)                        AS frequency_30d,
  MIN(transaction_date)           AS first_seen,
  MAX(transaction_date)           AS last_seen,
  SUM(amount_gbp)                 AS total_exposure_gbp,
  COUNT(DISTINCT merchant_name)   AS distinct_merchants,
  'Round-amount repetition'       AS alert_type,
  CASE
    WHEN COUNT(*) >= 10 AND SUM(amount_gbp) > 50000 THEN 'High'
    WHEN COUNT(*) >= 5  AND SUM(amount_gbp) > 20000 THEN 'Medium'
    ELSE 'Low'
  END AS alert_severity
FROM `retail_banking.fact_transactions`
WHERE
  transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  -- Round amounts: exactly divisible by 100 and above £500
  AND MOD(CAST(amount_gbp AS INT64), 100) = 0
  AND amount_gbp >= 500
  AND amount_gbp < 10000   -- below SARs threshold (already caught above)
GROUP BY customer_id, amount_gbp
HAVING COUNT(*) >= 5
ORDER BY total_exposure_gbp DESC;
