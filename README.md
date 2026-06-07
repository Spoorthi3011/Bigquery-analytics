# Retail Banking Analytics Platform — BigQuery

This is a portfolio project I built to simulate how a retail bank's data team might structure an analytics warehouse on Google BigQuery. It covers the kinds of problems that come up day-to-day in banking analytics — understanding your customers, spotting suspicious transactions, tracking product revenue, and predicting who's about to leave.

Everything here uses synthetic data, so there's no real customer information involved. The patterns and distributions are loosely based on industry benchmarks I researched while building this.

---

## Dashboard preview

![Banking Analytics Dashboard](docs/dashboard_preview.png)

*Executive dashboard showing KPIs, RFM segmentation, AML alerts, churn model scores, and NIM — built to reflect Looker Studio output from the BigQuery views in this repo.*

---

## What's in here

The project is split into five folders that mirror how a real analytics pipeline would be layered:

```
├── sql/
│   ├── 01_schema/              # Table definitions — how the warehouse is structured
│   ├── 02_data_ingestion/      # Scripts to generate synthetic data and load it
│   ├── 03_analysis/            # The core analytical queries
│   ├── 04_risk/                # Fraud and AML detection logic
│   └── 05_reporting/           # Monthly reporting views
├── dashboards/                 # Looker Studio data source config (JSON)
├── docs/                       # Data dictionary and architecture notes
└── README.md
```

---

## How the data flows

I modelled this after a standard banking data architecture — raw data lands in Cloud Storage, gets loaded into BigQuery staging tables, then transformed into a clean dimensional model that the analytics layer sits on top of.

```
Cloud Storage (raw files)
        ↓
BigQuery staging (partitioned tables, validated schema)
        ↓
Core model (dim_customers, dim_products, fact_transactions, fact_accounts)
        ↓
Analytics layer (segments, risk scores, product metrics)
        ↓
Reporting (Looker Studio dashboards, scheduled queries)
```

---

## Key analyses

| Analysis | What it does | File |
|---|---|---|
| RFM Segmentation | Scores customers on Recency, Frequency, Monetary value and groups them into 10 named segments | `03_analysis/rfm_segmentation.sql` |
| Churn Feature Engineering | Builds the feature table used to train the churn model | `03_analysis/churn_features.sql` |
| Churn Model (BQML) | Trains and scores a logistic regression model entirely in SQL | `03_analysis/bqml_churn.sql` |
| Cross-sell Opportunities | Identifies customers likely to take up a product they don't currently hold | `03_analysis/cross_sell_opportunities.sql` |
| AML Detection | Flags structuring patterns, velocity anomalies, and round-amount repetition | `04_risk/aml_structuring.sql` |
| Monthly P&L | Revenue breakdown by product and region, with NIM and month-on-month deltas | `05_reporting/monthly_pnl.sql` |

---

## BigQuery features I used

I tried to use this project to practise the features that actually matter in a production BigQuery environment, rather than just writing basic SELECT queries:

- **Partitioning and clustering** on the transactions table — filtering by date + customer_id keeps query costs low on a large table
- **Window functions** throughout — NTILE for RFM scoring, LAG for month-on-month comparisons, rolling SUMs for AML velocity checks
- **APPROX_QUANTILES** for percentile calculations on large datasets without full sorts
- **Materialised views** for the RFM output so dashboards don't re-scan 12 months of transactions on every load
- **BigQuery ML** — the churn model is trained and scored entirely in SQL using `CREATE MODEL` and `ML.PREDICT`
- **Parameterised queries** with `@param` syntax for the scheduled monthly reports
- **FARM_FINGERPRINT** for deterministic synthetic data generation — reproducible without an external seed file

---

## Sample output

**RFM segments (illustrative):**
```
Segment            Count     Avg CLV    Churn Risk
Champions          12,453    £4,820     Low
Loyal Customers    28,901    £2,340     Low
At Risk             9,234    £1,890     High
Hibernating        15,672      £430     Very High
```

**AML flags — last 30 days (illustrative):**
```
Flag type              Transactions    Value (£)
High-velocity spend         341         £892,340
Round-amount pattern        128       £3,200,000
Geographic anomaly           89         £234,110
```

---

## Running it yourself

You'll need a Google Cloud project with BigQuery enabled and the `gcloud` CLI set up.

```bash
# Clone the repo
git clone https://github.com/Spoorthi3011/Bigquery-analytics
cd Bigquery-analytics

# Set your project
export GCP_PROJECT="your-gcp-project-id"
export BQ_DATASET="retail_banking"

# Create the dataset (EU region — change if needed)
bq mk --dataset --location=EU $GCP_PROJECT:$BQ_DATASET

# Create tables
bq query --use_legacy_sql=false < sql/01_schema/create_tables.sql

# Generate synthetic data
bq query --use_legacy_sql=false < sql/02_data_ingestion/generate_synthetic_data.sql

# Run an analysis
bq query --use_legacy_sql=false < sql/03_analysis/rfm_segmentation.sql
```

Minimum IAM roles needed: `BigQuery Data Editor` and `BigQuery Job User`.

---

## Tech stack

| Tool | How I used it |
|---|---|
| Google BigQuery | Main data warehouse and SQL engine |
| Google Cloud Storage | Landing zone for raw data files |
| BigQuery ML | Churn prediction model — trained in SQL |
| Looker Studio | Dashboard layer (see `/dashboards`) |
| dbt | Optional transformation layer — config included if you prefer dbt over raw SQL |

---

## Data dictionary

Full field descriptions are in [`docs/data_dictionary.md`](docs/data_dictionary.md). The four main tables are:

- `dim_customers` — 100k synthetic customer records with segments, regions, and risk ratings
- `dim_products` — the full product catalogue (current accounts, savings, credit cards, mortgages, loans)
- `fact_transactions` — 5M+ synthetic transactions across 12 months, partitioned by date
- `fact_accounts` — monthly account snapshots with balances, utilisation, and arrears

---

## A note on the data

Everything is synthetic — generated procedurally using BigQuery's `FARM_FINGERPRINT` function so results are reproducible without needing external files. The churn rates, fraud rates, and product mix are modelled on published industry benchmarks, not real bank data.

---

## About this project

I built this to demonstrate BigQuery analytics skills in a financial services context. If you're looking at this for a data analyst role and want to talk through any of the queries or design decisions, feel free to reach out.
