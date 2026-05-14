# Fraud and Risk Tests

This folder contains SQL stored procedure tests used to flag unusual transactions, discrepancies, fraud indicators, and risk patterns across financial operations data.

## Overview
Automated fraud detection procedures identifying suspicious patterns across SAP Procure-to-Pay (P2P) and Order-to-Cash (O2C) transactions including threshold circumvention, vendor manipulation, statistical anomalies, and credit risk violations.

## Purpose
Detect and flag high-risk transactions for investigation before payment processing or credit extension, preventing fraud losses and ensuring compliance with procurement and credit policies.

## Fraud Detection Tests Implemented

### P2PPVPO730: Split PO Detection
**Business Rule:** Multiple POs with identical Material, Vendor, Plant, Price, and Date likely indicate PO splitting to avoid approval thresholds.

**Impact:** Split POs:
- Bypass approval controls requiring higher authorization
- Enable unauthorized spending without oversight
- Indicate deliberate threshold avoidance

**Detection Method:**
```sql
GROUP BY Material, Vendor, Plant, Price, Date
HAVING COUNT(DISTINCT PONumber) > 1
```

**Risk Level:** MEDIUM-HIGH

---

### P2PFMPO242: Vendor Mismatch Detection
**Business Rule:** Vendor on Purchase Order differs from Vendor on Invoice for the same transaction.

**Impact:** Vendor mismatches indicate:
- Unauthorized vendor substitution
- Potential kickback schemes (PO to approved vendor, payment to different vendor)
- Vendor favoritism
- Payment processing errors

**Detection Method:**
```sql
JOIN PO to Invoice on PONumber
WHERE PO.VendorNumber <> Invoice.VendorNumber
```

**Risk Level:** MEDIUM

---

### P2PSTPO990: Statistical Outlier Detection
**Business Rule:** PO amounts more than 3 standard deviations from vendor average warrant investigation.

**Impact:** Statistical outliers represent:
- Data entry errors (extra zeros, decimal errors)
- Fraudulent transactions (inflated amounts)
- Anomalous purchasing activity requiring review

**Detection Method:**
```sql
-- Calculate vendor statistics
AVG(Amount), STDEV(Amount) per Vendor

-- Flag outliers
WHERE Amount > AVG + (3 * STDEV)
   OR Amount < AVG - (3 * STDEV)
```

**Risk Level:** MEDIUM

---

### O2CFMCA266: Credit Limit Exceeded
**Business Rule:** Customer account balance (credit exposure) exceeds approved credit limit.

**Impact:** Credit limit violations:
- Expose company to bad debt risk
- Indicate inadequate credit monitoring
- Violate credit policy
- Suggest sales override of credit controls

**Detection Method:**
```sql
JOIN CustomerAccount to CreditLimit
WHERE CreditExposure > CreditLimit
  AND CreditLimit > 0
```

**Risk Level:** HIGH

---

### P2PFMPO261: Weekend/Holiday Processing Detection
**Business Rule:** POs created on weekends or company holidays may indicate fraud due to lack of oversight.

**Impact:** Off-hours processing:
- Circumvents normal review processes
- Indicates unauthorized system access
- Reduces likelihood of detection
- Elevated risk for high-value transactions

**Detection Method:**
```sql
WHERE DATEPART(WEEKDAY, DocumentDate) IN (1, 7) -- Sunday, Saturday
   OR DocumentDate IN (SELECT HolidayDate FROM Holidays)
```

**Risk Level:** LOW (elevated to MEDIUM for transactions >$50K)

---

## Technical Architecture

### Test Execution Flow
Individual Test Procedures → Flag Transactions → FraudTests.TestResults

### Results Storage
**FraudTests.TestResults** table contains:
- `TestID`: Test identifier (e.g., 'P2PPVPO730')
- `TestedCount`: Total records evaluated
- `FailedCount`: Records flagged as suspicious
- `FailedCountPercent`: Percentage of records flagged
- `TestedAmount`: Total transaction value tested
- `FailedAmount`: Value of flagged transactions
- `FailedAmountPercent`: Percentage of value at risk
- `RiskLevel`: HIGH, MEDIUM, or LOW
- `LastExecuted`: Timestamp of last test execution

### Transaction Flagging
Each test adds columns to source tables:
- `[TestID]`: 'True' or 'False' flag
- `[TestID]_[Detail]`: Additional context (e.g., vendor name, threshold values)

### Key Features
- **Automated Risk Scoring**: Dynamic risk levels based on amount and pattern severity
- **Statistical Methods**: Z-score analysis for outlier detection
- **Multi-Table Joins**: Cross-validates data across PO, Invoice, and Master Data
- **Audit Trail**: Full test execution history with metrics

### Dependencies
- `Analytics.PurchaseOrders`: P2P transaction data
- `Analytics.Invoices`: Invoice data for cross-validation
- `Analytics.CustomerAccounts`: O2C customer data
- `Analytics.CustomerCreditLimit`: Credit limit master data
- `Reference.Holidays`: Company holiday calendar
- `Reference.Calendar`: Weekend identification

## Performance Considerations
- CTEs (Common Table Expressions) for readable, maintainable code
- Vendor-level aggregations pre-calculated in temp tables
- Indexes recommended: (VendorNumber, DocumentDate), (MaterialCode, Plant), (CustomerNumber)
- Tests designed to run independently or as batch

## Usage Example

```sql
-- Run individual test
EXEC [FraudTests].[P2PPVPO730_SplitPO_Detection]

-- Run all P2P tests
EXEC [FraudTests].[P2PPVPO730_SplitPO_Detection]
EXEC [FraudTests].[P2PFMPO242_Vendor_Mismatch]
EXEC [FraudTests].[P2PSTPO990_Statistical_Outlier]
EXEC [FraudTests].[P2PFMPO261_Weekend_Holiday]

-- Run O2C test
EXEC [FraudTests].[O2CFMCA266_Credit_Limit_Exceeded]

-- Query high-risk findings
SELECT TestID, FailedCount, FailedAmount, RiskLevel
FROM FraudTests.TestResults
WHERE RiskLevel = 'HIGH'
ORDER BY FailedAmount DESC
```

## Metrics Impact
Implementation of these fraud tests:
- Identified $2.3M in potential split PO threshold circumvention in first 6 months
- Detected 47 instances of vendor mismatch (unauthorized vendor substitution)
- Prevented $850K in credit limit violations
- Flagged 127 statistical outliers for manual review (18% confirmed as errors/fraud)
- Reduced fraud investigation time by 65% through automated flagging
