-- ============================================================================
-- P2P FRAUD TEST: Vendor Mismatch Detection
-- ============================================================================
-- Test ID: P2PFMPO242
-- Business Rule: PO raised on vendor with different vendor ID between PO and Invoice
-- Risk Level: MEDIUM
-- Impact: Vendor favoritism, kickback schemes, unauthorized vendor substitution
-- ============================================================================

USE [P2P_FraudDetection]
GO

CREATE OR ALTER PROCEDURE [FraudTests].[P2PFMPO242_Vendor_Mismatch]
    @FileId VARCHAR(100) = NULL,
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @UserID UNIQUEIDENTIFIER = NULL
AS
BEGIN
    BEGIN TRY
        -- ====================================================================
        -- INITIALIZATION
        -- ====================================================================
        
        DECLARE @EXECUTION_STARTTIME DATETIME = GETDATE()
        DECLARE @PatternID NVARCHAR(20) = 'P2PFMPO242'
        DECLARE @SOURCETABLENAME NVARCHAR(100) = 'Analytics.PurchaseOrders'
        DECLARE @AMOUNTFIELD NVARCHAR(100) = 'NetOrderValue'

        -- ====================================================================
        -- SCHEMA VALIDATION - ADD TEST COLUMNS
        -- ====================================================================
        
        IF NOT EXISTS (
            SELECT * FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA + '.' + TABLE_NAME = @SOURCETABLENAME
              AND COLUMN_NAME = @PatternID
        )
        BEGIN
            EXEC sp_executesql N'
                ALTER TABLE Analytics.PurchaseOrders
                ADD P2PFMPO242 NVARCHAR(100) DEFAULT NULL,
                    P2PFMPO242_InvVendorNo NVARCHAR(100) NOT NULL DEFAULT(''''),
                    P2PFMPO242_InvVendorName NVARCHAR(500) NOT NULL DEFAULT('''')
            '
        END

        -- ====================================================================
        -- RESET FLAGS
        -- ====================================================================
        
        UPDATE Analytics.PurchaseOrders
        SET P2PFMPO242 = 'False',
            P2PFMPO242_InvVendorNo = '',
            P2PFMPO242_InvVendorName = ''

        -- ====================================================================
        -- FRAUD DETECTION LOGIC
        -- ====================================================================
        -- Business Rule: Vendor on PO differs from Vendor on Invoice
        --
        -- This pattern indicates:
        --   - Unauthorized vendor substitution
        --   - Potential kickback schemes (PO to approved vendor, invoice from different vendor)
        --   - Vendor favoritism
        --   - Payment processing to wrong vendor
        -- ====================================================================
        
        ;WITH Invoices AS (
            SELECT SystemInvoiceNo, FiscalYear, CompanyCode, 
                   VendorNumber, VendorName
            FROM Analytics.Invoices
            WHERE VendorNumber <> ''
        )
        UPDATE PO
        SET P2PFMPO242 = 'True',
            P2PFMPO242_InvVendorNo = ISNULL(INV.VendorNumber, ''),
            P2PFMPO242_InvVendorName = ISNULL(INV.VendorName, '')
        FROM Analytics.PurchaseOrders PO
        INNER JOIN Analytics.InvoiceLineItems ILI
            ON PO.PONumber = ILI.PONumber
            AND PO.POLineItem = ILI.POLineItem
        INNER JOIN Invoices INV
            ON ILI.SystemInvoiceNo = INV.SystemInvoiceNo
            AND ILI.FiscalYear = INV.FiscalYear
            AND ILI.CompanyCode = INV.CompanyCode
        WHERE PO.VendorNumber <> INV.VendorNumber
          AND PO.VendorNumber <> ''

        -- ====================================================================
        -- METRICS CALCULATION
        -- ====================================================================
        
        DECLARE @HITS BIGINT, @RECORDS BIGINT, 
                @AMOUNT DECIMAL(38,5), @FAILUREAMOUNT DECIMAL(38,5)

        SELECT @HITS = COUNT(*) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PFMPO242 = 'True'

        SELECT @RECORDS = COUNT(*) 
        FROM Analytics.PurchaseOrders

        SELECT @AMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders

        SELECT @FAILUREAMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PFMPO242 = 'True'

        -- ====================================================================
        -- RESULTS STORAGE
        -- ====================================================================
        
        UPDATE FraudTests.TestResults
        SET TestedCount = @RECORDS,
            FailedCount = @HITS,
            FailedCountPercent = CASE WHEN @RECORDS <> 0 
                                      THEN (CAST(@HITS AS FLOAT) / @RECORDS) * 100 
                                      ELSE 0 END,
            TestedAmount = @AMOUNT,
            FailedAmount = ISNULL(@FAILUREAMOUNT, 0),
            FailedAmountPercent = CASE WHEN @AMOUNT <> 0 
                                       THEN (ISNULL(@FAILUREAMOUNT, 0) / @AMOUNT) * 100 
                                       ELSE 0 END,
            LastExecuted = @EXECUTION_STARTTIME,
            RiskLevel = 'MEDIUM'
        WHERE TestID = @PatternID

        PRINT 'Test P2PFMPO242 completed: ' + CAST(@HITS AS VARCHAR) + ' findings'

    END TRY
    BEGIN CATCH
        -- ====================================================================
        -- ERROR HANDLING
        -- ====================================================================
        
        INSERT INTO [App].[ErrorLog] (
            ProcedureName, ErrorMessage, ErrorLine, ErrorSeverity, 
            ErrorState, ErrorNumber, CorrelationID, UserID, EntityID
        )
        SELECT 
            @PatternID, ERROR_MESSAGE(), ERROR_LINE(), ERROR_SEVERITY(),
            ERROR_STATE(), ERROR_NUMBER(), @CorrelationID, @UserID, @FileId
    END CATCH
END
GO
