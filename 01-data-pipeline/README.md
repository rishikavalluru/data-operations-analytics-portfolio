# Data Pipeline

This section explains the end-to-end data pipeline used to move financial operations data from source files into reporting, risk review, and dashboard outputs.

The pipeline supports multiple finance workflows, including Procure to Pay, Order to Cash, and Travel & Expense. The SQL examples and dashboards in this portfolio use P2P and O2C data, but the structure is designed as a repeatable data operations flow applicable across financial datasets.

## Pipeline Flow

```text
SAP Source Files (BSEG, LFA1, EKKO, EKPO)
↓
Raw Data Import
↓
Data Quality Checks (DQC)
↓
Data Staging (Business Object Mapping)
↓
Data Validations / Control Checks (DCC)
↓
Data Mapping (PO → Invoice → Payment → GL)
↓
SQL Test Execution (40+ fraud/risk detection tests)
↓
Risk Scoring & Test Hits
↓
Analytical Views (Entity-level + Transaction-level)
↓
Dashboards & Review Workflow

## Step-by-Step Breakdown

| Step | Stage | What Happens | Output |
|------|-------|--------------|--------|
| 1 | **Source Files** | Financial data is received from SAP modules (P2P, O2C, T&E). Files include purchase orders, invoices, payments, vendors, customers, expenses, and general ledger data. | Source files ready for import |
| 2 | **Raw Data Import** | Source files are loaded into raw tables. File metadata is tracked: source table type, record count, load status, created/modified timestamps, and processing phase. | Raw imported tables |
| 3 | **Data Quality Checks (DQC)** | Imported records are validated for completeness, consistency, duplicates, missing critical fields, and invalid formats. | DQC-passed records + quality issue log |
| 4 | **Data Staging** | Raw data is transformed into business objects (VendorMaster, PurchaseOrders, Invoices, Payments, CustomerMaster, ExpenseClaims) for validation and analysis. | Staged business objects |
| 5 | **Data Validations (DCC)** | Business rules and control checks are applied. Records failing validation are excluded or flagged. Examples: missing payment terms, blocked vendors, invalid vendor-PO relationships. | Validated, analysis-ready records |
| 6 | **Data Mapping** | Business objects are linked across workflows: PO → Invoice → Payment → GL. Creates unified entity views (e.g., vendor spend across PO, invoice, payment). | Mapped P2P/O2C entities |
| 7 | **SQL Test Execution** | 40+ SQL stored procedures detect fraud and risk patterns: split POs, duplicate payments, vendor mismatches, weekend activity, statistical outliers, conflict of interest. | Test hits (flagged transactions) |
| 8 | **Risk Scoring** | Test results are converted into risk scores. Flags are prioritized by amount, severity, and test category. | Scored risk data |
| 9 | **Analytical Views** | **Entity View**: Vendor/customer-level risk aggregation with composite scores. **Transaction View**: Flagged PO/invoice/payment details for investigation. | Entity-level + transaction-level views |
| 10 | **Dashboards & Review** | Risk scores and flagged transactions surface in Power BI dashboards. Finance and operations teams review exceptions, drill into details, and take action. | Dashboards + review workflow |

## Key Design Principles

**Separation of Concerns**: Data quality (DQC) validates technical correctness; data validation (DCC) enforces business rules. This prevents bad data from reaching fraud tests while keeping validation logic maintainable.

**Test-Driven Detection**: Fraud and risk detection runs as discrete SQL tests (stored procedures), not monolithic queries. Each test focuses on one pattern, making logic transparent and results auditable.

**Dual-Layer Analysis**: Entity View enables vendor/customer risk ranking; Transaction View enables transaction-level investigation. Teams can start broad (which vendors are risky?) and drill down (which POs are flagged?).

**Quality Gates**: Only DQC-passed data moves to staging; only DCC-validated data reaches test execution. This prevents false positives from incomplete or inconsistent data.

## Business Value

This pipeline creates a repeatable process for turning high-volume financial datasets into clean, reviewable outputs that teams can trust and act on.

**It supports**:
- Fraud and risk detection (split POs, duplicate payments, vendor anomalies)
- Exception tracking and flagged transaction review
- Financial operations reporting (AR, AP, procurement, expense)
- Data quality monitoring and validation
- Entity-level risk ranking and transaction-level drill-down
- Reducing manual spreadsheet review by 35-40%

## Pipeline Implementation

The SQL code, test procedures, and analytical views that implement this pipeline are documented in:
- [`/02-sql-analysis`](../02-sql-analysis) - DQC, staging, validation, mapping, and fraud detection tests
- [`/03-dashboard-reporting`](../03-dashboard-reporting) - Entity View, Transaction View, and dashboard examples
