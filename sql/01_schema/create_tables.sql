-- =============================================================================
-- FILE: 01_schema/create_tables.sql
-- DESC: Core schema for retail banking analytics warehouse
-- NOTE: All tables partitioned by date, clustered for cost efficiency
-- =============================================================================

-- -----------------------------------------------------------------------------
-- DATASET SETUP
-- -----------------------------------------------------------------------------
-- Run: bq mk --dataset --location=EU your_project:retail_banking

-- -----------------------------------------------------------------------------
-- DIM: CUSTOMERS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.dim_customers`
(
  customer_id       STRING    NOT NULL,
  first_name        STRING,
  last_name         STRING,
  date_of_birth     DATE,
  age_band          STRING,   -- e.g. '25-34', '35-44'
  gender            STRING,
  postcode_district STRING,   -- e.g. 'SW1', 'M1'
  region            STRING,   -- e.g. 'London', 'North West'
  country           STRING    DEFAULT 'GB',
  customer_since    DATE,
  customer_segment  STRING,   -- 'Retail', 'Premier', 'Private'
  is_student        BOOL      DEFAULT FALSE,
  is_business       BOOL      DEFAULT FALSE,
  kyc_status        STRING,   -- 'Verified', 'Pending', 'Failed'
  risk_rating       STRING,   -- 'Low', 'Medium', 'High'
  relationship_mgr  STRING,
  nps_score         INT64,    -- Net Promoter Score (-100 to 100)
  created_at        TIMESTAMP,
  updated_at        TIMESTAMP
)
OPTIONS (
  description = 'Customer master data — one row per customer'
);

-- -----------------------------------------------------------------------------
-- DIM: PRODUCTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.dim_products`
(
  product_id        STRING    NOT NULL,
  product_code      STRING,   -- e.g. 'CA_ADVANCE', 'CC_PLATINUM'
  product_name      STRING,
  product_type      STRING,   -- 'Current Account', 'Savings', 'Credit Card', 'Mortgage', 'Loan'
  product_family    STRING,   -- 'Deposits', 'Lending', 'Payments'
  interest_rate     NUMERIC,  -- Annual rate (%)
  fee_monthly       NUMERIC,
  credit_limit_max  NUMERIC,
  is_active         BOOL      DEFAULT TRUE,
  launch_date       DATE,
  retired_date      DATE
)
OPTIONS (
  description = 'Product catalogue — all banking products offered'
);

-- -----------------------------------------------------------------------------
-- FACT: TRANSACTIONS
-- Partitioned by transaction_date for cost-efficient querying
-- Clustered by customer_id + transaction_type for common filter patterns
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.fact_transactions`
(
  transaction_id        STRING    NOT NULL,
  customer_id           STRING    NOT NULL,
  account_id            STRING    NOT NULL,
  product_id            STRING,
  transaction_date      DATE      NOT NULL,
  transaction_timestamp TIMESTAMP NOT NULL,
  transaction_type      STRING,   -- 'Debit', 'Credit', 'Transfer', 'ATM'
  transaction_category  STRING,   -- 'Groceries', 'Utilities', 'Entertainment', etc.
  merchant_name         STRING,
  merchant_category_code STRING,  -- MCC code
  merchant_country      STRING    DEFAULT 'GB',
  amount_gbp            NUMERIC   NOT NULL,
  running_balance_gbp   NUMERIC,
  channel               STRING,   -- 'Mobile', 'Online', 'Branch', 'ATM', 'POS'
  is_international      BOOL      DEFAULT FALSE,
  is_recurring          BOOL      DEFAULT FALSE,
  is_flagged            BOOL      DEFAULT FALSE,  -- AML/fraud flag
  flag_reason           STRING,
  batch_load_timestamp  TIMESTAMP
)
PARTITION BY transaction_date
CLUSTER BY customer_id, transaction_type
OPTIONS (
  description       = 'All customer transactions — partitioned daily, clustered by customer',
  partition_expiration_days = 1825  -- 5-year retention
);

-- -----------------------------------------------------------------------------
-- FACT: ACCOUNTS
-- One row per account per month (slowly changing snapshot)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.fact_accounts`
(
  account_id            STRING    NOT NULL,
  customer_id           STRING    NOT NULL,
  product_id            STRING    NOT NULL,
  snapshot_month        DATE      NOT NULL,   -- First day of month
  account_status        STRING,   -- 'Active', 'Dormant', 'Closed', 'Overdrawn'
  balance_gbp           NUMERIC,
  credit_limit_gbp      NUMERIC,
  utilisation_pct       NUMERIC,  -- Credit utilisation %
  days_in_arrears       INT64     DEFAULT 0,
  missed_payments_3m    INT64     DEFAULT 0,
  interest_charged_gbp  NUMERIC,
  fees_charged_gbp      NUMERIC,
  interest_earned_gbp   NUMERIC,
  opened_date           DATE,
  closed_date           DATE
)
PARTITION BY snapshot_month
CLUSTER BY customer_id, product_id
OPTIONS (
  description = 'Monthly account-level snapshot — balances, utilisation, arrears'
);

-- -----------------------------------------------------------------------------
-- DIM: DATE (Calendar table for time intelligence)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.dim_date`
(
  date_id           DATE      NOT NULL,
  year              INT64,
  quarter           INT64,
  month             INT64,
  month_name        STRING,
  week_of_year      INT64,
  day_of_week       INT64,
  day_name          STRING,
  is_weekend        BOOL,
  is_uk_bank_holiday BOOL,
  fiscal_year       INT64,    -- HSBC fiscal year (Jan-Dec)
  fiscal_quarter    STRING    -- e.g. 'FY2024-Q3'
)
OPTIONS (
  description = 'Calendar dimension for time-based joins and fiscal reporting'
);

-- -----------------------------------------------------------------------------
-- REFERENCE: MERCHANT CATEGORY CODES
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_banking.ref_merchant_categories`
(
  mcc_code          STRING    NOT NULL,
  mcc_description   STRING,
  spending_category STRING,   -- Aggregated category for analytics
  is_high_risk      BOOL      DEFAULT FALSE  -- AML risk indicator
)
OPTIONS (
  description = 'MCC code lookup for transaction categorisation'
);
