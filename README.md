#  Retail Banking Analytics Platform — BigQuery

> End-to-end data analytics pipeline simulating a retail banking environment, built on Google BigQuery. Covers customer segmentation, transaction fraud detection, product performance, and regulatory reporting.

---

## 📌 Project Overview

This project demonstrates a production-style analytics workflow for a retail bank, using BigQuery as the central data warehouse. It includes schema design, data modelling, advanced SQL analytics, and business intelligence outputs relevant to roles in financial services data analysis.

**Business domains covered:**
- Customer lifetime value & segmentation
- Transaction monitoring & anomaly detection
- Product portfolio performance (loans, cards, savings)
- AML (Anti-Money Laundering) pattern queries
- Regulatory-style reporting (PNL, exposure, churn)

---

## 🗂️ Repository Structure

```
├── sql/
│   ├── 01_schema/              # DDL — table definitions & partitioning strategy
│   ├── 02_data_ingestion/      # Synthetic data generation & staging scripts
│   ├── 03_analysis/            # Core analytical queries
│   ├── 04_risk/                # Fraud & AML detection logic
│   └── 05_reporting/           # Scheduled reporting views & aggregations
├── dashboards/                 # Looker Studio / Data Studio JSON configs
├── docs/                       # Architecture diagrams & data dictionary
└── README.md
```

---

## 🧱 Data Architecture

```
Raw Layer (GCS)
    └── Cloud Storage buckets (transactions, customers, products)
          │
          ▼
Staging Layer (BigQuery)
    └── Partitioned tables, schema validation
          │
          ▼
Core Layer (BigQuery — Modelled)
    └── dim_customers, dim_products, fact_transactions, fact_accounts
          │
          ▼
Analytics Layer (BigQuery Views)
    └── Customer segments, risk scores, product metrics
          │
          ▼
Reporting Layer
    └── Looker Studio dashboards / Scheduled queries
```

---

## 🔑 Key Analyses

| Analysis | Description | SQL File |
|---|---|---|
| Customer Segmentation (RFM) | Recency, Frequency, Monetary scoring | `03_analysis/rfm_segmentation.sql` |
| Churn Prediction Features | Feature engineering for ML pipeline | `03_analysis/churn_features.sql` |
| Product Cross-sell | Customers missing high-value products | `03_analysis/cross_sell_opportunities.sql` |
| Transaction Anomaly Detection | Z-score & IQR-based flagging | `04_risk/anomaly_detection.sql` |
| AML Structuring Detection | Round-amount & layering patterns | `04_risk/aml_structuring.sql` |
| Monthly PNL View | Revenue by product & region | `05_reporting/monthly_pnl.sql` |
| Regulatory Exposure Report | Large exposure concentration | `05_reporting/large_exposure.sql` |

---

## ⚙️ BigQuery Features Used

- **Partitioning** — by transaction date for cost-optimised querying
- **Clustering** — on `customer_id` and `product_type` for scan reduction
- **Window Functions** — RANK, LEAD/LAG, ROW_NUMBER for time-series analysis
- **Approximate Aggregations** — `APPROX_QUANTILES`, `APPROX_COUNT_DISTINCT` for large datasets
- **Scripting & Procedures** — Stored procedures for scheduled refresh logic
- **Parameterised Queries** — Using `@param` syntax for reusable report templates
- **Materialised Views** — Pre-aggregated product performance metrics
- **BigQuery ML** — Logistic regression for churn scoring (see `03_analysis/bqml_churn.sql`)

---

## 🚀 Getting Started

### Prerequisites
- Google Cloud project with BigQuery API enabled
- `gcloud` CLI authenticated
- Roles: `BigQuery Data Editor`, `BigQuery Job User`

### Setup

```bash
# 1. Clone the repo
git clone https://github.com/Spoorthi3011/Bigquery-analytics
cd Bigquery-project

# 2. Set your project ID
export GCP_PROJECT="your-gcp-project-id"
export BQ_DATASET="retail_banking"

# 3. Create the dataset
bq mk --dataset --location=EU $GCP_PROJECT:$BQ_DATASET

# 4. Run schema creation
bq query --use_legacy_sql=false < sql/01_schema/create_tables.sql

# 5. Load synthetic data
bq query --use_legacy_sql=false < sql/02_data_ingestion/generate_synthetic_data.sql

# 6. Run analytics layer
bq query --use_legacy_sql=false < sql/03_analysis/rfm_segmentation.sql
```

---

## 📊 Sample Outputs

### Customer RFM Segmentation
```
Segment          | Count   | Avg CLV  | Churn Risk
Champions        | 12,453  | £4,820   | Low
Loyal Customers  | 28,901  | £2,340   | Low
At Risk          | 9,234   | £1,890   | High
Hibernating      | 15,672  | £430     | Very High
```

### Fraud Flag Summary (Last 30 Days)
```
Flag Type            | Transactions | Amount (£)  | Recall Rate
High-velocity        | 341          | £892,340    | 94%
Round-amount AML     | 128          | £3,200,000  | 87%
Geographic anomaly   | 89           | £234,110    | 91%
```

---

## 🛠️ Tech Stack

| Tool | Purpose |
|---|---|
| Google BigQuery | Core data warehouse & SQL engine |
| Google Cloud Storage | Raw data landing zone |
| BigQuery ML | In-database ML (churn model) |
| Looker Studio | Dashboard & visualisation |
| dbt (optional) | Transformation layer (config in `/dbt`) |
| Python (optional) | Data generation scripts |

---

## 📄 Data Dictionary

See [`docs/data_dictionary.md`](docs/data_dictionary.md) for full field descriptions.

Key tables:
- `dim_customers` — 100k synthetic customer records
- `dim_products` — Current account, savings, credit card, mortgage, loan
- `fact_transactions` — 5M+ synthetic transactions (12 months)
- `fact_accounts` — Account-level balances and status

---

## 📝 Notes

All data in this project is **fully synthetic** — generated procedurally to reflect realistic banking distributions. No real customer data is used. Patterns (fraud rates, churn rates, product mix) are loosely based on published industry benchmarks.

---

## 📬 Contact

Built as a portfolio project demonstrating BigQuery analytics skills for financial services roles.
