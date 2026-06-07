-- =============================================================================
-- FILE: 02_data_ingestion/generate_synthetic_data.sql
-- DESC: Generate realistic synthetic banking data directly in BigQuery
--       No external files needed — runs entirely in SQL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Populate dim_date (2022-01-01 to 2024-12-31)
-- -----------------------------------------------------------------------------
INSERT INTO `retail_banking.dim_date`
SELECT
  d                                                       AS date_id,
  EXTRACT(YEAR  FROM d)                                   AS year,
  EXTRACT(QUARTER FROM d)                                 AS quarter,
  EXTRACT(MONTH FROM d)                                   AS month,
  FORMAT_DATE('%B', d)                                    AS month_name,
  EXTRACT(ISOWEEK FROM d)                                 AS week_of_year,
  EXTRACT(DAYOFWEEK FROM d)                               AS day_of_week,
  FORMAT_DATE('%A', d)                                    AS day_name,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7)                     AS is_weekend,
  d IN (                                                  -- UK bank holidays 2022-2024
    DATE '2022-01-03', DATE '2022-04-15', DATE '2022-04-18',
    DATE '2022-05-02', DATE '2022-06-02', DATE '2022-06-03',
    DATE '2022-08-29', DATE '2022-09-19', DATE '2022-12-26', DATE '2022-12-27',
    DATE '2023-01-02', DATE '2023-04-07', DATE '2023-04-10',
    DATE '2023-05-01', DATE '2023-05-08', DATE '2023-05-29',
    DATE '2023-08-28', DATE '2023-12-25', DATE '2023-12-26',
    DATE '2024-01-01', DATE '2024-03-29', DATE '2024-04-01',
    DATE '2024-05-06', DATE '2024-05-27', DATE '2024-08-26',
    DATE '2024-12-25', DATE '2024-12-26'
  )                                                       AS is_uk_bank_holiday,
  EXTRACT(YEAR FROM d)                                    AS fiscal_year,
  CONCAT('FY', EXTRACT(YEAR FROM d), '-Q', EXTRACT(QUARTER FROM d)) AS fiscal_quarter
FROM
  UNNEST(GENERATE_DATE_ARRAY('2022-01-01', '2024-12-31', INTERVAL 1 DAY)) AS d;

-- -----------------------------------------------------------------------------
-- STEP 2: Populate dim_products
-- -----------------------------------------------------------------------------
INSERT INTO `retail_banking.dim_products` VALUES
  ('PRD001', 'CA_ADVANCE',   'Advance Current Account',   'Current Account', 'Deposits', 0.00,  0.00,    NULL,        TRUE, '2015-01-01', NULL),
  ('PRD002', 'CA_SELECT',    'Select Current Account',    'Current Account', 'Deposits', 0.00, 12.95,    NULL,        TRUE, '2018-06-01', NULL),
  ('PRD003', 'SA_FLEX',      'Flexible Saver',            'Savings',         'Deposits', 3.50,  0.00,    NULL,        TRUE, '2020-01-01', NULL),
  ('PRD004', 'SA_FIXED12',   'Fixed Rate Bond 12M',       'Savings',         'Deposits', 5.10,  0.00,    NULL,        TRUE, '2023-01-01', NULL),
  ('PRD005', 'SA_ISA',       'Cash ISA',                  'Savings',         'Deposits', 3.80,  0.00,    NULL,        TRUE, '2016-04-06', NULL),
  ('PRD006', 'CC_PLATINUM',  'Platinum Credit Card',      'Credit Card',     'Lending',  22.90,  0.00, 15000.00,     TRUE, '2019-03-01', NULL),
  ('PRD007', 'CC_CASHBACK',  'Cashback Credit Card',      'Credit Card',     'Lending',  19.90,  0.00, 10000.00,     TRUE, '2021-01-01', NULL),
  ('PRD008', 'LN_PERSONAL',  'Personal Loan',             'Loan',            'Lending',   8.90,  0.00,    NULL,        TRUE, '2017-01-01', NULL),
  ('PRD009', 'LN_VEHICLE',   'Vehicle Finance Loan',      'Loan',            'Lending',   6.50,  0.00,    NULL,        TRUE, '2020-06-01', NULL),
  ('PRD010', 'MG_RESIDENTIAL','Residential Mortgage',     'Mortgage',        'Lending',   4.25,  0.00,    NULL,        TRUE, '2010-01-01', NULL),
  ('PRD011', 'MG_BTL',       'Buy-to-Let Mortgage',       'Mortgage',        'Lending',   5.10,  0.00,    NULL,        TRUE, '2012-01-01', NULL);

-- -----------------------------------------------------------------------------
-- STEP 3: Generate synthetic customers (100,000 rows)
-- Uses BigQuery's GENERATE_ARRAY and pseudo-random logic
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `retail_banking.dim_customers` AS
WITH
  seed AS (
    SELECT id
    FROM UNNEST(GENERATE_ARRAY(1, 100000)) AS id
  ),
  regions AS (
    SELECT * FROM UNNEST([
      STRUCT('London' AS region, 'SW1' AS postcode),
      STRUCT('London', 'EC1'),
      STRUCT('South East', 'RG1'),
      STRUCT('North West', 'M1'),
      STRUCT('Yorkshire', 'LS1'),
      STRUCT('Scotland', 'EH1'),
      STRUCT('Midlands', 'B1'),
      STRUCT('South West', 'BS1')
    ])
  ),
  base AS (
    SELECT
      id,
      CONCAT('CUST', LPAD(CAST(id AS STRING), 8, '0'))  AS customer_id,
      MOD(ABS(FARM_FINGERPRINT(CAST(id * 7 AS STRING))), 8) AS region_idx,
      DATE_SUB(CURRENT_DATE(), INTERVAL CAST(20 + MOD(ABS(FARM_FINGERPRINT(CAST(id AS STRING))), 45) AS INT64) YEAR)
        AS approx_dob,
      DATE_SUB(CURRENT_DATE(), INTERVAL CAST(1 + MOD(ABS(FARM_FINGERPRINT(CAST(id * 3 AS STRING))), 15) AS INT64) YEAR)
        AS customer_since,
      MOD(ABS(FARM_FINGERPRINT(CAST(id * 11 AS STRING))), 100) AS rand_segment,
      MOD(ABS(FARM_FINGERPRINT(CAST(id * 13 AS STRING))), 100) AS rand_risk,
      MOD(ABS(FARM_FINGERPRINT(CAST(id * 17 AS STRING))), 2)   AS gender_flag
    FROM seed
  )
SELECT
  b.customer_id,
  CONCAT('First', CAST(b.id AS STRING))     AS first_name,   -- placeholder
  CONCAT('Last', CAST(b.id AS STRING))      AS last_name,
  b.approx_dob                              AS date_of_birth,
  CASE
    WHEN EXTRACT(YEAR FROM AGE(b.approx_dob)) BETWEEN 18 AND 24 THEN '18-24'
    WHEN EXTRACT(YEAR FROM AGE(b.approx_dob)) BETWEEN 25 AND 34 THEN '25-34'
    WHEN EXTRACT(YEAR FROM AGE(b.approx_dob)) BETWEEN 35 AND 44 THEN '35-44'
    WHEN EXTRACT(YEAR FROM AGE(b.approx_dob)) BETWEEN 45 AND 54 THEN '45-54'
    WHEN EXTRACT(YEAR FROM AGE(b.approx_dob)) BETWEEN 55 AND 64 THEN '55-64'
    ELSE '65+'
  END                                       AS age_band,
  IF(b.gender_flag = 0, 'M', 'F')          AS gender,
  r.postcode                                AS postcode_district,
  r.region,
  'GB'                                      AS country,
  b.customer_since,
  CASE
    WHEN b.rand_segment < 70 THEN 'Retail'
    WHEN b.rand_segment < 92 THEN 'Premier'
    ELSE 'Private'
  END                                       AS customer_segment,
  (b.rand_segment < 15)                     AS is_student,
  FALSE                                     AS is_business,
  'Verified'                                AS kyc_status,
  CASE
    WHEN b.rand_risk < 75 THEN 'Low'
    WHEN b.rand_risk < 93 THEN 'Medium'
    ELSE 'High'
  END                                       AS risk_rating,
  CONCAT('RM_', LPAD(CAST(MOD(b.id, 500) AS STRING), 4, '0')) AS relationship_mgr,
  CAST(MOD(ABS(FARM_FINGERPRINT(CAST(b.id * 23 AS STRING))), 201) - 100 AS INT64) AS nps_score,
  TIMESTAMP(b.customer_since)               AS created_at,
  CURRENT_TIMESTAMP()                       AS updated_at
FROM base b
JOIN (
  SELECT ROW_NUMBER() OVER () - 1 AS idx, region, postcode
  FROM regions
) r ON b.region_idx = r.idx;

-- NOTE: fact_transactions and fact_accounts would be generated similarly.
-- For large-scale generation (5M+ rows), use a Python script with
-- the BigQuery Storage Write API or load from GCS.
-- See: docs/data_generation_guide.md for the Python approach.
