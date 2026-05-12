# Data Operations Analytics Portfolio

This portfolio demonstrates end-to-end data operations work: building SQL pipelines that turn high-volume financial datasets into reporting that finance and operations teams can review, trust, and act on.

The work spans data quality checks, staging, validation, mapping, SQL-based fraud detection, risk scoring, and dashboard reporting. This repository showcases a **representative SAP Procure-to-Pay fraud detection project** from a portfolio of enterprise implementations across technology, consumer goods, and manufacturing sectors.

## Portfolio Focus
- Financial operations reporting (AR, AP, procurement, expense)
- Data quality, mapping, staging, and validation
- SQL-based fraud and risk detection
- Entity-level and transaction-level analytical views
- Exception tracking and flagged transaction review
- Dashboard reporting for finance and operations teams
- Reducing manual spreadsheet review through structured SQL workflows

## Tools & Technologies
- **SQL**: SQL Server, T-SQL, stored procedures
- **ETL**: SSIS
- **Data Sources**: SAP (P2P, O2C, T&E modules)
- **Visualization**: Power BI, Tableau
- **Workflow**: Azure DevOps, Excel

## Repository Structure
| Section | Contents |
|---------|----------|
| [`01-data-pipeline`](./01-data-pipeline) | End-to-end pipeline architecture from SAP source to dashboards |
| [`02-sql-analysis`](./02-sql-analysis) | Data quality checks, staging, validation, mapping, and fraud tests |
| [`03-dashboard-reporting`](./03-dashboard-reporting) | Entity View, Transaction View, and reporting examples |
| [`04-business-impact`](./04-business-impact) | Metrics, outcomes, and business value delivered |
| [`assets`](./assets) | Screenshots and supporting visuals |

## Pipeline Overview
```text
SAP Source Files 
   ↓
Raw Data Import
   ↓
Data Quality Checks (DQC)
   ↓
Data Staging (Business Object Mapping)
   ↓
Data Validation (Business Rules & Controls)
   ↓
Data Mapping 
   ↓
SQL Test Execution (Fraud/risk detection tests)
   ↓
Risk Scoring & Test Hits
   ↓
Analytical Views (Entity-level + Transaction-level)
   ↓
Dashboards & Review Workflow
```
## Aggregate Results Across Projects
- **500,000+** transactions processed
- **4** enterprise implementations (global technology, consumer goods, professional services, manufacturing)
- **$10M+** in flagged amounts and risk exposure identified
- **200+** high-risk entities surfaced (vendors, customers, employees)
- **1,500+** transactions flagged for missing controls (payment terms, approvals, documentation)
- **35-40%** reduction in manual review time across implementations

## Featured Project: SAP P2P Fraud Detection
*Representative example from portfolio - Global technology company*

- **93,586** purchase orders tested
- **35,000+** flagged transactions
- **$2.5M+** flagged amount for review
- **50** high-risk vendors identified
- **401** POs with missing payment terms
- **35%** reduction in procurement review time

## Contact
**Rishika Reddy Valluru**  
📧 rishikavalluru3@gmail.com  
💼 [LinkedIn](www.linkedin.com/in/rishikareddyvalluru)
