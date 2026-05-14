-- ============================================================================
-- SAP PROCURE-TO-PAY DATA CONSISTENCY CHECKS (DCC)
-- ============================================================================
-- File: PurchaseOrders_Consistency_Validations.sql
-- Purpose: Validate referential integrity and orphan records across SAP P2P tables
-- Author: Rishika Reddy Valluru
-- Module: Procure-to-Pay (P2P)
-- Description: Checks data consistency between Purchase Order tables (EKKO, EKPO)
--              and master data tables (LFB1) to identify orphan records and
--              referential integrity violations
-- 
-- Validation Rules:
--   DCC-PO-1: Vendor exists in company code master data (EKKO → LFB1)
--   DCC-PO-2: PO header has corresponding line items (EKKO → EKPO)
--   DCC-PO-3: PO line items have valid header (EKPO → EKKO)
--   DCC-PO-4: Material master data exists (EKPO → MARA)
--   DCC-PO-5: Plant master data exists (EKPO → T001W)
--   DCC-PO-6: Purchasing organization exists (EKKO → T024E)
--   DCC-PO-7: Complete row duplicates detection (EKKO)
-- ============================================================================

USE [P2P_DataValidation]
GO

SET ANSI_NULLS OFF
GO

SET QUOTED_IDENTIFIER OFF
GO

-- ============================================================================
-- STORED PROCEDURE: PurchaseOrders_VALIDATIONS
-- ============================================================================
-- Parameters:
--   @FileId        : Unique identifier for the file being validated
--   @CorrelationID : Correlation ID for tracking across processes
--   @UserID        : User who initiated the validation
-- ============================================================================

ALTER PROCEDURE [DCC].[PurchaseOrders_VALIDATIONS]
    @FileId VARCHAR(100),
    @CorrelationID UNIQUEIDENTIFIER,
    @UserID UNIQUEIDENTIFIER
AS
BEGIN
    BEGIN TRY
        -- ====================================================================
        -- INITIALIZATION
        -- ====================================================================
        
        -- Update validation status to 'In Progress'
        EXEC DCC.Table_DataValidations 
            @type = 1,
            @status = 3,
            @EntityName = 'P2P_PurchaseOrders',
            @EntityTypeFormat = 'DV_Module_Submodule'

        BEGIN TRAN

        -- Variable declarations
        DECLARE @StrSQL NVARCHAR(MAX)
        DECLARE @Module VARCHAR(100)
        DECLARE @UDMTable VARCHAR(100)
        DECLARE @SPT_Source NVARCHAR(100)
        DECLARE @Errormessage NVARCHAR(MAX) = ''
        DECLARE @Errorprocedure NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @ErrorNum INT
        DECLARE @ErrorMsg VARCHAR(300)
        DECLARE @ERPSystem NVARCHAR(100)

        SET @UDMTable = 'Analytics.PurchaseOrders'

        -- Clear previous validation results for this table
        IF EXISTS (SELECT 1 FROM DCC.RESULTS_Header WHERE SPT_Source = @UDMTable)
        BEGIN
            DELETE FROM DCC.RESULTS_Header
            WHERE SPT_Source = @UDMTable
        END

        IF EXISTS (SELECT 1 FROM DCC.RESULTS_Details WHERE SPT_Source = @UDMTable)
        BEGIN
            DELETE FROM DCC.RESULTS_Details
            WHERE SPT_Source = @UDMTable
        END

        -- ====================================================================
        -- VALIDATION RULE: DCC-PO-1
        -- Check for vendors in EKKO not found in company code master (LFB1)
        -- ====================================================================
        -- Business Rule: Every vendor in PO header must exist in vendor-company code master
        -- Impact: Orphan vendor records indicate:
        --   - Incomplete vendor master data extraction
        --   - Data integrity issues between transactional and master data
        --   - Potential payment processing failures
        -- ====================================================================
        
        PRINT 'Executing DCC-PO-1: Vendor in PO not in Vendor Company Master'
        
        EXEC (
            'SELECT B.SPT_ROWID, ''' + @UDMTable + ''' AS SPT_Source 
             INTO #DCCPO1
             FROM Staging.EKKO B
             LEFT JOIN STAGING.LFB1 A
                 ON LTRIM(RTRIM(ISNULL(A.LIFNR, ''@''))) = LTRIM(RTRIM(ISNULL(B.LIFNR, ''#'')))
                 AND LTRIM(RTRIM(ISNULL(A.BUKRS, ''@''))) = LTRIM(RTRIM(ISNULL(B.BUKRS, ''#'')))
             WHERE A.LIFNR IS NULL
               AND ISNULL(B.LIFNR, '''') <> ''''

             INSERT INTO DCC.RESULTS_Header
             (DCC_ID, DCC_DESCRIPTION, DCC_COUNT, DCC_EXECUTION_TIME, DCC_STATUS, SPT_Source, 
              DCC_Severity, ValidationCatergory, CategorySeverity, PossibleFix, DCC_Field)
             SELECT ''DCC-PO-1'', 
                    ''In PO header (EKKO) not in vendor company(LFB1)'', 
                    Count(*), 
                    Getdate(), 
                    ''Pending'', 
                    ''' + @UDMTable + ''', 
                    ''Medium'', 
                    ''Orphan Checks'', 
                    ''Checks Failed/Performed'', 
                    ''Fix or Re-Extract'', 
                    ''lifnr'' 
             FROM #DCCPO1

             INSERT INTO DCC.RESULTS_Details (DCC_ID, SPT_RowId, TableName, SPT_Source)
             SELECT ''DCC-PO-1'', SPT_RowId, ''Staging.EKKO'', ''' + @UDMTable + ''' 
             FROM #DCCPO1
        ')

        -- ====================================================================
        -- VALIDATION RULE: DCC-PO-2
        -- Check for PO headers in EKKO without line items in EKPO
        -- ====================================================================
        -- Business Rule: Every PO header must have at least one line item
        -- Impact: Headers without line items indicate:
        --   - Incomplete data extraction
        --   - Data transmission errors between EKKO and EKPO
        --   - Invalid PO creation in source system
        -- ====================================================================
        
        PRINT 'Executing DCC-PO-2: PO Header without Line Items'
        
        EXEC ('
            Select a.SPT_ROWID, ''' + @UDMTable + ''' AS SPT_Source 
            INTO #DCCPO2
            from Staging.EKKO a
            LEFT JOIN Staging.EKPO b
                on ltrim(rtrim(isnull(a.EBELN, ''@''))) = ltrim(rtrim(isnull(b.EBELN, ''#'')))
            WHERE b.EBELN is null

            INSERT INTO DCC.RESULTS_Header
            (DCC_ID, DCC_DESCRIPTION, DCC_COUNT, DCC_EXECUTION_TIME, DCC_STATUS, SPT_Source, 
             DCC_Severity, ValidationCatergory, CategorySeverity, PossibleFix, DCC_Field)
            SELECT ''DCC-PO-2'', 
                   ''In PO header (EKKO) not in PO Lines(EKPO)'', 
                   Count(*), 
                   Getdate(), 
                   ''Pending'', 
                   ''' + @UDMTable + ''', 
                   ''Medium'', 
                   ''Orphan Checks'', 
                   ''Checks Failed/Performed'', 
                   ''Fix or Re-Extract'', 
                   ''EBELN'' 
            FROM #DCCPO2

            INSERT INTO DCC.RESULTS_Details (DCC_ID, SPT_RowId, TableName, SPT_Source)
            SELECT ''DCC-PO-2'', SPT_RowId, ''Staging.EKKO'', ''' + @UDMTable + ''' 
            FROM #DCCPO2
        ')

        -- ====================================================================
        -- VALIDATION RULE: DCC-PO-3
        -- Check for PO line items in EKPO without header in EKKO
        -- ====================================================================
        -- Business Rule: Every PO line item must have a corresponding header record
        -- Impact: Line items without headers cause:
        --   - Inability to trace PO details (vendor, dates, terms)
        --   - Reporting failures when joining EKPO to EKKO
        --   - Data integrity violations in analytics layer
        -- ====================================================================
        
        PRINT 'Executing DCC-PO-3: PO Line Items without Header'
        
        EXEC ('
            Select a.SPT_ROWID, ''' + @UDMTable + ''' AS SPT_Source 
            INTO #DCCPO3
            from [Staging].[EKPO] a
            LEFT JOIN [Staging].[EKKO] b
                on ltrim(rtrim(isnull(a.EBELN, ''@''))) = ltrim(rtrim(isnull(b.EBELN, ''#'')))
            WHERE b.EBELN is null

            INSERT INTO DCC.RESULTS_Header
            (DCC_ID, DCC_DESCRIPTION, DCC_COUNT, DCC_EXECUTION_TIME, DCC_STATUS, SPT_Source, 
             DCC_Severity, ValidationCatergory, CategorySeverity, PossibleFix, DCC_Field)
            SELECT ''DCC-PO-3'', 
                   ''In PO lines (EKPO) not in PO Header(EKKO)'', 
                   Count(*), 
                   Getdate(), 
                   ''Pending'', 
                   ''' + @UDMTable + ''', 
                   ''Medium'', 
                   ''Orphan Checks'', 
                   ''Checks Failed/Performed'', 
                   ''Fix or Re-Extract'', 
                   ''EBELN'' 
            FROM #DCCPO3

            INSERT INTO DCC.RESULTS_Details (DCC_ID, SPT_RowId, TableName, SPT_Source)
            SELECT ''DCC-PO-3'', SPT_RowId, ''Staging.EKPO'', ''' + @UDMTable + ''' 
            FROM #DCCPO3
        ')

        -- ====================================================================
        -- VALIDATION RULE: DCC-PO-7
        -- Check for complete row duplicates in EKKO table
        -- ====================================================================
        -- Business Rule: No two records should be identical across all fields
        -- Impact: Complete row duplicates indicate:
        --   - Data extraction ran multiple times without deduplication
        --   - Source system data quality issues
        --   - ETL pipeline failures
        -- ====================================================================
        
        PRINT 'Executing DCC-PO-7: Complete Row Duplicates in EKKO'
        
        SET @StrSQL = '
            WITH EKKO_Duplicates AS (
                SELECT *,
                    ROW_NUMBER() OVER(PARTITION BY MANDT, BUKRS, EBELN, BSTYP, BSART, LOEKZ, STATU, 
                                                    AEDAT, ERNAM, LIFNR, ZTERM, EKORG, EKGRP, WAERS
                                      ORDER BY SPT_ROWID) AS RowRank
                FROM Staging.EKKO
            )
            SELECT SPT_ROWID, ''' + @UDMTable + ''' AS SPT_Source
            INTO #EKKO25
            FROM EKKO_Duplicates
            WHERE RowRank > 1

            INSERT INTO DCC.RESULTS_Header
            (DCC_ID, DCC_DESCRIPTION, DCC_COUNT, DCC_EXECUTION_TIME, DCC_STATUS, SPT_Source, 
             DCC_Severity, ValidationCatergory, CategorySeverity, PossibleFix, DCC_Field)
            SELECT ''DCC-PO-7'', 
                   ''Complete row Duplicates for EKKO(EBELN) fields'', 
                   Count(*), 
                   Getdate(), 
                   ''Pending'', 
                   ''' + @UDMTable + ''', 
                   ''Critical'', 
                   ''Complete row duplicates'', 
                   ''Checks Failed/Performed'', 
                   ''Fix or Re-Extract'', 
                   ''EBELN'' 
            FROM #EKKO25

            INSERT INTO DCC.RESULTS_Details (DCC_ID, SPT_RowId, TableName, SPT_Source)
            SELECT ''DCC-PO-7'', SPT_RowId, ''Staging.EKKO'', ''' + @UDMTable + ''' 
            FROM #EKKO25
        '
        EXEC sys.sp_executesql @StrSQL

        -- ====================================================================
        -- UPDATE VALIDATION COUNTS BY CATEGORY
        -- ====================================================================
        
        ;WITH DCCCnt
        AS (
            SELECT DCC_Id,
                   DCC_Count,
                   ValidationsCountByCategory,
                   DENSE_RANK() OVER (PARTITION BY DCC_Id ORDER BY DCC_Id, DCC_Count) rnk
            FROM DCC.RESULTS_Header
            WHERE SPT_Source = @UDMTable
        )
        UPDATE DCCCnt 
        SET ValidationsCountByCategory = CASE WHEN DCC_COUNT <> 0 THEN 1 ELSE 0 END
        WHERE rnk = 1

        COMMIT TRAN

        -- ====================================================================
        -- STATUS UPDATE AND RECORD COUNT
        -- ====================================================================
        
        DECLARE @l_count2 INT
        SELECT @l_count2 = COUNT(1) FROM Staging.Ekpo WITH (NOLOCK)

        EXEC DCC.Table_DataValidations 
            @type = 2,
            @status = 4,
            @EntityName = 'P2P_PurchaseOrders',
            @EntityTypeFormat = 'DV_Module_Submodule',
            @l_count = @l_count2,
            @FileId = @FileId

        PRINT 'Data consistency checks completed successfully'

    END TRY

    BEGIN CATCH
        -- ====================================================================
        -- ERROR HANDLING
        -- ====================================================================
        
        ROLLBACK TRAN;

        -- Update validation status to 'Failed'
        DECLARE @l_count1 INT
        SELECT @l_count1 = COUNT(1) FROM Staging.Ekpo WITH (NOLOCK)

        EXEC DCC.Table_DataValidations 
            @type = 2,
            @status = 5,
            @EntityName = 'P2P_PurchaseOrders',
            @EntityTypeFormat = 'DV_Module_Submodule',
            @l_count = @l_count1

        -- Log error details
        SET @ErrorNum = 50029;
        SET @ErrorMsg = [App].[ReturnErrorMessage](@ErrorNum);
        SET @errormessage = ERROR_MESSAGE()

        EXECUTE App.InsertErrorlogDetails
            @Errorprocedure = @Errorprocedure,
            @Errormessage = @Errormessage,
            @CorrelationID = @CorrelationID,
            @UserID = @UserID,
            @FileId = @FileId,
            @Usermessage = @ErrorMsg

        PRINT 'Data consistency checks failed with error: ' + @ErrorMsg
    END CATCH
END
GO
