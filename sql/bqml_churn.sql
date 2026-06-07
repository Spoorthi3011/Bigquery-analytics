-- =============================================================================
-- FILE: 03_analysis/bqml_churn.sql
-- DESC: Train a churn prediction model using BigQuery ML
--       Algorithm: Logistic Regression (interpretable, fast, banking-appropriate)
--       Input: ml_churn_features table (see churn_features.sql)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Train the model
-- Run time: ~2-5 minutes for 100k rows
-- -----------------------------------------------------------------------------
CREATE OR REPLACE MODEL `retail_banking.mdl_churn_logistic`
OPTIONS (
  model_type           = 'LOGISTIC_REG',
  input_label_cols     = ['churned'],
  data_split_method    = 'RANDOM',
  data_split_eval_fraction = 0.2,
  max_iterations       = 50,
  l1_reg               = 0.1,
  l2_reg               = 0.1,
  auto_class_weights   = TRUE   -- handle class imbalance (churn is rare)
) AS
SELECT
  -- Features
  age,
  tenure_years,
  customer_segment,
  region,
  txn_count_6m,
  total_spend_6m,
  avg_txn_amount_6m,
  unique_categories,
  active_months_6m,
  days_since_last_txn,
  mobile_txns,
  spend_trend_pct,
  product_count,
  avg_credit_utilisation,
  max_days_in_arrears,
  total_missed_payments_3m,
  overdrawn_accounts,
  dormant_accounts,
  nps_score,
  -- Label
  churned
FROM `retail_banking.ml_churn_features`
WHERE feature_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);  -- latest snapshot


-- -----------------------------------------------------------------------------
-- STEP 2: Evaluate model performance
-- -----------------------------------------------------------------------------
SELECT
  *
FROM ML.EVALUATE(
  MODEL `retail_banking.mdl_churn_logistic`,
  (
    SELECT * FROM `retail_banking.ml_churn_features`
    WHERE feature_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  )
);
-- Expected metrics (illustrative):
--   precision:  ~0.72   (of predicted churners, 72% actually churn)
--   recall:     ~0.68   (of actual churners, 68% are caught)
--   f1_score:   ~0.70
--   roc_auc:    ~0.84


-- -----------------------------------------------------------------------------
-- STEP 3: Score all active customers
-- Produces churn probability for each customer
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `retail_banking.churn_scores` AS
SELECT
  f.customer_id,
  f.customer_segment,
  f.region,
  f.tenure_years,
  f.days_since_last_txn,
  f.product_count,
  pred.predicted_churned_probs[OFFSET(1)].prob  AS churn_probability,
  pred.predicted_churned                         AS predicted_churned,

  -- Segment into action tiers
  CASE
    WHEN pred.predicted_churned_probs[OFFSET(1)].prob >= 0.75 THEN 'Imminent (75%+)'
    WHEN pred.predicted_churned_probs[OFFSET(1)].prob >= 0.50 THEN 'High Risk (50-75%)'
    WHEN pred.predicted_churned_probs[OFFSET(1)].prob >= 0.25 THEN 'At Risk (25-50%)'
    ELSE 'Low Risk (<25%)'
  END AS churn_tier,

  CURRENT_TIMESTAMP() AS scored_at

FROM `retail_banking.ml_churn_features` f
JOIN ML.PREDICT(
  MODEL `retail_banking.mdl_churn_logistic`,
  TABLE `retail_banking.ml_churn_features`
) pred
  ON f.customer_id = pred.customer_id

ORDER BY churn_probability DESC;


-- -----------------------------------------------------------------------------
-- STEP 4: Feature importance — understand key churn drivers
-- -----------------------------------------------------------------------------
SELECT
  *
FROM ML.WEIGHTS(MODEL `retail_banking.mdl_churn_logistic`)
ORDER BY ABS(weight) DESC;

-- Typical top drivers:
--   days_since_last_txn    (strong positive — longer gap = more churn risk)
--   spend_trend_pct        (strong negative — declining spend predicts churn)
--   product_count          (negative — more products = more sticky)
--   total_missed_payments  (positive — arrears are pre-churn signal)
--   nps_score              (negative — higher NPS = lower churn)
