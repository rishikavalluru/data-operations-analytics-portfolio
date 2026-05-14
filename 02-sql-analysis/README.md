# SQL Analysis

This section documents the SQL logic used across the data pipeline: data quality checks, staging, validation, mapping, fraud detection tests, and analytical views for review.

The SQL work shown here demonstrates how raw financial data is cleaned, validated, structured, tested for fraud and risk indicators, and transformed into review-ready outputs that finance and operations teams can act on without manually sorting through large datasets.

## SQL Components

| Component | Purpose |
|-----------|---------|
| **Data Quality Checks (DQC)** | Validates completeness, format, and uniqueness of imported records. Checks for missing critical fields, invalid formats, and duplicate records before data moves to staging. |
| **Staging** | Transforms raw SAP tables into business objects (VendorMaster, PurchaseOrders, Invoices, Payments, CustomerMaster, ExpenseClaims) for validation and analysis. |
| **Data Validations (DCC)** | Enforces referential integrity and business rules. Validates that records link together correctly, flags orphan records and duplicates. |
| **Mapping** | Consolidates multiple source files into unified business objects. Creates clean, analysis-ready records from fragmented SAP tables. |
| **Fraud & Risk Tests** | 100+ SQL stored procedures detect fraud patterns and risk indicators across categories: Fraud Monitoring, High Risk Analysis, Conflict of Interest, Anti-Corruption, Statistical Testing, Internal Controls, Revenue Leakage. |
| **Entity View** | Aggregates transaction-level flags to entity level (vendor, customer, employee). Calculates composite risk scores for ranking and prioritization. |
| **Transaction View** | Surfaces flagged transaction details for investigation. Provides drill-down from entity-level risk to specific transactions. |
| **Risk Ranking** | Prioritizes flagged entities and transactions by risk score, flagged amount, and test severity for review workflow. |

## Folder Structure

```text
02-sql-analysis/
│
├── data-quality-checks/
│   ├── README.md
│   └── dqc.sql
│
├── staging/
│   ├── README.md
│   └── Staging.sql
│
├── validation-checks/
│   ├── README.md
│   └── dcc.sql
│
├── mapping/
│   ├── README.md
│   └── Mapping.sql
│
└── fraud-risk-tests/
    ├── README.md
    ├── P2PPVPO730_split_po_detection.sql
    ├── P2PFMPO242_vendor_mismatch.sql
    ├── P2PSTPO990_statistical_outlier.sql
    ├── O2CFMCA266_credit_limit_exceeded.sql
    └── P2PFMPO261_weekend_holiday_processing.sql

```

## Test Categories

The fraud and risk tests span multiple risk categories:

- **Fraud Monitoring**: Split POs, duplicate payments, vendor mismatches, weekend/holiday activity, price variance, statistical outliers
- **High Risk Analysis**: High-risk countries, OFAC screening, Panama Papers matching, vendor risk assessment
- **Conflict of Interest**: Duplicate vendor setup, employee-vendor relationships, vendor address matching
- **Anti-Corruption**: Government entity keywords, PEP (Politically Exposed Persons) screening
- **Statistical Testing**: Mean ± 3σ outlier detection, Z-score analysis, volume anomalies
- **Internal Controls**: Missing payment terms, missing approvals, threshold bypass detection
- **Revenue Leakage**: Pricing integrity, rebate fraud, billing discrepancies

## SQL Techniques Demonstrated

This portfolio showcases SQL proficiency across:

- **Complex CTEs and window functions** (DENSE_RANK, ROW_NUMBER, PARTITION BY for fraud pattern detection)
- **Self-joins and comparative analysis** (price variance, duplicate detection)
- **Statistical calculations** (AVG, STDEV, Z-scores for outlier detection)
- **Dynamic SQL and stored procedures** (parameterized test execution framework)
- **Referential integrity validation** (orphan detection, cross-table consistency checks)
- **Data aggregation and scoring** (entity-level risk scoring, composite risk calculations)
- **Temp tables and performance optimization** (staged calculations for complex test logic)

## Business Value

The SQL work in this section enabled:

- **35-40% reduction** in manual review time across implementations
- **$10M+ in flagged amounts** identified for investigation
- **200+ high-risk entities** surfaced (vendors, customers, employees)
- **Automated exception detection** replacing manual spreadsheet review
- **Consistent, auditable** fraud detection logic across modules

## How to Navigate This Section

Each subfolder contains:
- **README.md**: Explains what that stage/component does, inputs, outputs, business logic
- **SQL files**: Actual code with header comments explaining purpose, logic, and business rules
- **Code snippets**: Key logic excerpts showcasing SQL techniques used

Start with the README in each folder for context, then review the SQL files for implementation details.
