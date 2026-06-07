# Data Dictionary

## Overview

All tables live in the `retail_banking` BigQuery dataset. The model follows a **star schema** with dimension tables (prefixed `dim_`) and fact tables (prefixed `fact_`). Views and materialised views are prefixed `v_` and `mv_` respectively.

---

## dim_customers

One row per customer. Updated daily via CDC from source CRM system.

| Field | Type | Description |
|---|---|---|
| `customer_id` | STRING | Primary key — format `CUST00000001` |
| `date_of_birth` | DATE | Used for age-band derivation |
| `age_band` | STRING | Bucketed: `18-24`, `25-34`, `35-44`, `45-54`, `55-64`, `65+` |
| `customer_segment` | STRING | `Retail` (mass market), `Premier` (£50k+ relationship), `Private` (£500k+) |
| `kyc_status` | STRING | `Verified`, `Pending`, `Failed` — filter to Verified for most analytics |
| `risk_rating` | STRING | Internal AML risk score: `Low`, `Medium`, `High` |
| `nps_score` | INT64 | Net Promoter Score from most recent survey, range -100 to 100 |
| `customer_since` | DATE | Date of first product opening |

---

## dim_products

Product catalogue — one row per product. Stable reference data.

| Field | Type | Description |
|---|---|---|
| `product_id` | STRING | Primary key — format `PRD001` |
| `product_code` | STRING | Business code, e.g. `CA_ADVANCE`, `CC_PLATINUM` |
| `product_type` | STRING | `Current Account`, `Savings`, `Credit Card`, `Mortgage`, `Loan` |
| `product_family` | STRING | Broad grouping: `Deposits`, `Lending`, `Payments` |
| `interest_rate` | NUMERIC | Annual % rate — 0.00 for current accounts |
| `is_active` | BOOL | FALSE for retired products (still held by legacy customers) |

---

## fact_transactions

Core transactional fact table. Partitioned by `transaction_date`. **Always filter on `transaction_date` to avoid full table scans.**

| Field | Type | Description |
|---|---|---|
| `transaction_id` | STRING | Primary key |
| `customer_id` | STRING | FK → dim_customers |
| `account_id` | STRING | FK → fact_accounts |
| `transaction_date` | DATE | **Partition key** — always include in WHERE |
| `transaction_type` | STRING | `Debit`, `Credit`, `Transfer`, `ATM` |
| `transaction_category` | STRING | Derived from MCC: `Groceries`, `Utilities`, `Transport`, etc. |
| `merchant_category_code` | STRING | ISO 18245 MCC code |
| `amount_gbp` | NUMERIC | Always positive — use `transaction_type` for direction |
| `channel` | STRING | `Mobile`, `Online`, `Branch`, `ATM`, `POS` |
| `is_flagged` | BOOL | AML/fraud flag — exclude from customer analytics queries |

**Partition & clustering:** Partitioned daily, clustered on `(customer_id, transaction_type)`. Most queries filtering on customer + date range will scan <1% of total data.

---

## fact_accounts

Monthly snapshot of each account's state. Append-only — one row per `(account_id, snapshot_month)`.

| Field | Type | Description |
|---|---|---|
| `account_id` | STRING | Account identifier |
| `snapshot_month` | DATE | First day of month — **partition key** |
| `account_status` | STRING | `Active`, `Dormant`, `Closed`, `Overdrawn` |
| `balance_gbp` | NUMERIC | End-of-month balance (negative = overdrawn) |
| `utilisation_pct` | NUMERIC | Credit utilisation % (credit cards only) |
| `days_in_arrears` | INT64 | Count of days past due at snapshot date |
| `missed_payments_3m` | INT64 | Rolling 3-month missed payment count |
| `interest_charged_gbp` | NUMERIC | Interest charged to customer in the month |
| `interest_earned_gbp` | NUMERIC | Interest credited to customer (savings) in the month |

---

## Analytical Views

| View | Description | Refresh |
|---|---|---|
| `v_monthly_pnl` | Revenue by product × region × month | On-demand |
| `mv_customer_rfm` | RFM segmentation (materialised) | Daily |
| `aml_structuring_alerts` | Sub-threshold credit pattern flags | Daily |
| `aml_velocity_alerts` | Unusual spend velocity flags | Daily |
| `aml_round_amount_alerts` | Round-amount repetition flags | Daily |

---

## ML Models

| Model | Algorithm | Purpose | AUC |
|---|---|---|---|
| `mdl_churn_logistic` | Logistic Regression (BQML) | 90-day churn probability | ~0.84 |

---

## Cost Optimisation Notes

- Always filter on partition keys (`transaction_date`, `snapshot_month`)
- Use `APPROX_COUNT_DISTINCT` for high-cardinality count-distinct on large tables
- The `mv_customer_rfm` materialised view avoids rescanning 12 months of transactions for every dashboard load
- `INFORMATION_SCHEMA.JOBS` can be queried to monitor slot usage and identify expensive queries

---

## Naming Conventions

| Prefix | Meaning |
|---|---|
| `dim_` | Dimension table |
| `fact_` | Fact table |
| `v_` | View |
| `mv_` | Materialised view |
| `aml_` | AML/risk monitoring view |
| `ml_` | ML feature table or training data |
| `mdl_` | BigQuery ML model |
| `ref_` | Reference/lookup table |
