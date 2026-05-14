-- ============================================================================
-- SAP PROCURE-TO-PAY DATA QUALITY VALIDATIONS
-- ============================================================================
-- Purpose: Comprehensive data quality checks for SAP Purchase Order Line Items (EKPO)
-- Author: Rishika Reddy Valluru
-- Module: Procure-to-Pay (P2P)
-- Description: Validates data integrity, completeness, and consistency across
--              SAP EKPO extracts including duplicate detection, missing key fields,
--              date validation, and unicode character verification
-- ============================================================================

USE [P2P_DataQuality]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- STORED PROCEDURE: EKPO_VALIDATIONS
-- ============================================================================
-- Parameters:
--   @TableName     : Name of the raw data table to validate
--   @TableType     : Type identifier (e.g., 'EKPO' for Purchase Order Line Items)
--   @FileId        : Unique identifier for the uploaded file
--   @CorrelationID : Correlation ID for tracking across processes
--   @UserID        : User who initiated the validation
--   @Module        : Module name (e.g., 'P2P', 'O2C')
-- ============================================================================

ALTER PROCEDURE [DQC].[EKPO_VALIDATIONS] (
    @TableName VARCHAR(100),
    @TableType VARCHAR(50),
    @FileId UNIQUEIDENTIFIER,
    @CorrelationID UNIQUEIDENTIFIER,
    @UserID UNIQUEIDENTIFIER,
    @Module NVARCHAR(100)
)
AS
BEGIN
    BEGIN TRY
        -- ====================================================================
        -- INITIALIZATION
        -- ====================================================================
        
        -- Update validation status to 'In Progress'
        EXEC [DQC].[Template_DataQuality] 
            @Type = 1,
            @EntityTypeId = 3,
            @Status = 3,
            @FileId = @FileId,
            @TableType = @TableType

        -- Variable declarations
        DECLARE @StrSQL NVARCHAR(MAX)
        DECLARE @SPT_Source NVARCHAR(100)
        DECLARE @ColumnImportance NVARCHAR(100) = ''
        DECLARE @DateValidationTable NVARCHAR(100) = '[DQC].[DateValidations'
        DECLARE @ID NVARCHAR(100)
        DECLARE @FileUploadID INT
        DECLARE @Errormessage NVARCHAR(MAX) = ''
        DECLARE @Errorprocedure NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @ErrorNum INT
        DECLARE @ErrorMsg VARCHAR(300)
        DECLARE @UID NVARCHAR(100)
        DECLARE @SQL NVARCHAR(MAX)
        DECLARE @Exclusion NVARCHAR(MAX)

        -- Build exclusion criteria for soft-deleted records
        EXEC [DQC].[Template_ParameterConcatenation] 'EKPO', @Exclusion OUTPUT
        PRINT @Exclusion

        -- Backup amount and date fields before validation
        EXEC Staging.AmountDateBackup 
            @TABLENAME = @TABLENAME,
            @TEMPLATENAME = @TABLETYPE,
            @FileId = @FileId,
            @Module = @Module

        -- Execute generic data checks
        EXEC Staging.[Datacheck] 
            @Rawtable = @TableName,
            @TemplateName = @TableType,
            @Module = @Module

        -- Get File Upload ID for audit logging
        SELECT @FileUploadID = FileUploadID
        FROM DM.File_Details
        WHERE Rowid = @FileId

        SELECT @UID = @UserID

        -- Extract source system identifier from the data
        SET @StrSQL = 'SELECT DISTINCT @SPT_Source=SPT_Source FROM ' + @TableName + ''
        EXEC sys.sp_executesql @StrSQL,
            N'@SPT_Source NVARCHAR(100) OUTPUT',
            @SPT_Source = @SPT_Source OUTPUT

        -- Clear previous validation results for this table
        DELETE FROM DQC.RESULTS_Details
        WHERE TableName = @TableName
            AND SPT_Source = @SPT_Source

        -- ====================================================================
        -- VALIDATION RULE: EKPO-002
        -- Check for duplicate unique keys (MANDT, EBELN, EBELP)
        -- ====================================================================
        -- Business Rule: Each combination of Client (MANDT), Purchase Order Number (EBELN),
        --                and Line Item (EBELP) must be unique
        -- Impact: Duplicates cause reporting inconsistencies and financial misstatements
        -- ====================================================================
        
        IF EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA + '.' + TABLE_NAME = PARSENAME(@TableName, 2) + '.' + PARSENAME(@TableName, 1)
              AND COLUMN_NAME IN ('MANDT', 'EBELN', 'EBELP')
            GROUP BY TABLE_SCHEMA, TABLE_NAME
            HAVING COUNT(DISTINCT COLUMN_NAME) = 3 -- Ensure all required columns exist
        )
        BEGIN
            PRINT 'Executing EKPO-002: Duplicate Unique Key Check'

            SET @StrSQL = '
                WITH CTE2 AS (
                    SELECT SPT_ROWID, SPT_Source,
                        COUNT(*) OVER(PARTITION BY s.MANDT, S.EBELN, S.EBELP) AS RANKA
                    FROM ' + @TableName + ' s 
                    WHERE IsSoftDelete <> 1
                )
                INSERT INTO DQC.RESULTS_Details(DQC_ID, SPT_RowId, TableName, SPT_Source)
                SELECT ''EKPO-002'', SPT_ROWID, ''' + @TableName + ''', SPT_Source 
                FROM CTE2
                WHERE RANKA > 1
            '
            PRINT @StrSQL
            EXEC sys.sp_executesql @StrSQL
        END

        -- ====================================================================
        -- VALIDATION RULE: EKPO-003
        -- Check for missing unique key fields (MANDT, EBELN, EBELP)
        -- ====================================================================
        -- Business Rule: Purchase Order Line Items table must contain all unique key fields
        -- Impact: Missing key fields prevent proper transaction matching and reconciliation
        -- ====================================================================
        
        IF NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE '[' + TABLE_SCHEMA + '].[' + table_name + ']' = @TableName
              AND COLUMN_NAME = 'EBELN'
        )
        OR NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE '[' + TABLE_SCHEMA + '].[' + table_name + ']' = @TableName
              AND COLUMN_NAME = 'EBELP'
        )
        BEGIN
            PRINT 'Executing EKPO-003: Missing Unique Key Fields'
            
            SELECT @StrSQL = (
                'INSERT INTO DQC.RESULTS_Details(DQC_ID, SPT_RowId, TableName, SPT_Source)
                 SELECT ''EKPO-003'', 0, ''' + @TableName + ''', ''' + @SPT_Source + '''
                '
            )
            EXEC sys.sp_executesql @StrSQL
        END

        -- ====================================================================
        -- VALIDATION RULE: EKPO-004
        -- Check for missing deletion indicator field (LOEKZ)
        -- ====================================================================
        -- Business Rule: Deletion indicator field is required to track cancelled line items
        -- Impact: Without LOEKZ, cancelled items may be incorrectly included in reporting
        -- ====================================================================
        
        IF NOT EXISTS (
            SELECT *
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE '[' + TABLE_SCHEMA + '].[' + table_name + ']' = @TableName
                AND COLUMN_NAME = 'LOEKZ'
        )
        BEGIN
            PRINT 'Executing EKPO-004: Missing Deletion Indicator Field'
            
            SELECT @StrSQL = (
                'INSERT INTO DQC.RESULTS_Details(DQC_ID, SPT_RowId, TableName, SPT_Source)
                 SELECT ''EKPO-004'', 0, ''' + @TableName + ''', ''' + @SPT_Source + '''
                '
            )
            EXEC sys.sp_executesql @StrSQL
        END

        -- ====================================================================
        -- VALIDATION RULE: EKPO-049
        -- Validate date format in BEDAT field (Document Date)
        -- ====================================================================
        -- Business Rule: Date fields must conform to valid SAP date formats (YYYYMMDD)
        -- Impact: Invalid dates cause reporting failures and incorrect aging analysis
        -- Method: Uses custom IsValidDate function to handle SAP-specific date formats
        -- ====================================================================
        
        IF EXISTS (
            SELECT *
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE '[' + TABLE_SCHEMA + '].[' + table_name + ']' = @TableName
                AND COLUMN_NAME = 'BEDAT'
        )
        BEGIN
            PRINT 'Executing EKPO-049: Date Validation for BEDAT Field'
            
            SELECT @ID = NEWID()

            SET @StrSQL = '
                SET NOCOUNT ON

                -- Create temporary table for date validation results
                DROP TABLE IF EXISTS ' + @DateValidationTable + @ID + ']

                CREATE TABLE ' + @DateValidationTable + @ID + '] (
                    [ID] INT IDENTITY(1,1),
                    [SPT_RowID] INT,
                    [SPT_Source] [nvarchar](255) NULL,
                    [ColumnValue] [nvarchar](50) NULL,
                    [IsValid] BIT
                )

                -- Insert potentially invalid dates for validation
                INSERT INTO ' + @DateValidationTable + @ID + '] ([SPT_RowID], [SPT_Source], [ColumnValue])
                SELECT SPT_ROWID, SPT_Source, [BEDAT] 
                FROM ' + @TableName + '
                WHERE ISDATE(BEDAT) <> 1 
                   OR (ISDATE(BEDAT) = 1 AND (LEN(BEDAT) NOT BETWEEN 8 AND 10 OR BEDAT LIKE ''%:%'')) 
                   ' + @Exclusion + '

                -- Get distinct invalid dates for batch validation
                DROP TABLE IF EXISTS #DISTDATES
                CREATE TABLE #DISTDATES (
                    [ID] INT IDENTITY(1,1),
                    [ColumnValue] [nvarchar](50) NULL
                )

                INSERT INTO #DISTDATES
                SELECT DISTINCT [BEDAT] 
                FROM ' + @TableName + '
                WHERE ISDATE(BEDAT) <> 1 
                   OR (ISDATE(BEDAT) = 1 AND (LEN(BEDAT) NOT BETWEEN 8 AND 10 OR BEDAT LIKE ''%:%'')) 
                   ' + @Exclusion + '

                -- Validate each distinct date using custom SAP date validation logic
                DECLARE @I INT = 1,
                        @Date NVARCHAR(50),
                        @Output BIT,
                        @OutputDate DATE

                WHILE (@I <= (SELECT COUNT(1) FROM #DISTDATES))
                BEGIN
                    SELECT @Date = [ColumnValue] FROM #DISTDATES WHERE ID = @I
                    
                    -- Call custom date validation function for SAP date formats
                    EXEC [DQC].[IsValidDate] 
                        @SAP_DATE = @Date,
                        @Result = @Output OUTPUT,
                        @ConvertedDate = @OutputDate OUTPUT
                    
                    UPDATE ' + @DateValidationTable + @ID + '] 
                    SET [IsValid] = @Output 
                    WHERE [ColumnValue] = @Date
                    
                    SET @I = @I + 1
                END

                -- Insert validation failures into results table
                INSERT INTO DQC.RESULTS_Details(DQC_ID, SPT_RowId, TableName, SPT_Source)
                SELECT ''EKPO-049'', SPT_ROWID, ''' + @TableName + ''', SPT_Source 
                FROM ' + @DateValidationTable + @ID + '] 
                WHERE [IsValid] = 0

                -- Cleanup temporary table
                DROP TABLE IF EXISTS ' + @DateValidationTable + @ID + ']
            '
            EXEC sys.sp_executesql @StrSQL
        END

        -- ====================================================================
        -- VALIDATION RULE: EKPO-050
        -- Check for missing unicode characters in TXZ01 field (Short Text)
        -- ====================================================================
        -- Business Rule: Text fields should not contain placeholder characters (####, ????)
        --                indicating unicode conversion failures
        -- Impact: Corrupted text data reduces data quality and usability for reporting
        -- ====================================================================
        
        IF EXISTS (
            SELECT *
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE '[' + TABLE_SCHEMA + '].[' + table_name + ']' = @TableName
                AND COLUMN_NAME = 'TXZ01'
        )
        BEGIN
            PRINT 'Executing EKPO-050: Unicode Character Validation'
            
            EXEC (
                'INSERT INTO DQC.RESULTS_Details(DQC_ID, SPT_RowId, TableName, SPT_Source)
                 SELECT ''EKPO-050'', SPT_ROWID, ''' + @TableName + ''', SPT_Source 
                 FROM ' + @TableName + ' 
                 WHERE [IsSoftDelete] <> 1
                   AND (LTRIM(RTRIM(TXZ01)) LIKE ''%####%'' 
                        OR LTRIM(RTRIM(ISNULL(TXZ01,''''))) LIKE ''%????%'') 
                   ' + @Exclusion + '
                '
            )
        END

        -- ====================================================================
        -- EXECUTE COMMON CALCULATION VALIDATIONS
        -- ====================================================================
        -- Executes shared validation logic for amount calculations and
        -- cross-field consistency checks
        -- ====================================================================
        
        EXEC [DQC].[COM_CALC_VALIDATIONS]
            @TableName = @TableName,
            @TableType = @TableType,
            @FileId = @FileId,
            @CorrelationID = @CorrelationID,
            @UserID = @UserID,
            @SPT_Source = @SPT_Source

    END TRY

    BEGIN CATCH
        -- ====================================================================
        -- ERROR HANDLING
        -- ====================================================================
        
        -- Update validation status to 'Failed'
        EXEC [DQC].[Template_DataQuality]
            @Type = 1,
            @EntityTypeId = 3,
            @Status = 5,
            @FileId = @FileId,
            @TableType = @TableType

        -- Update file audit timestamp
        UPDATE FA
        SET [ModifiedOn] = GETUTCDATE()
        FROM [App].[FileAudit] FA
        WHERE FA.FileUploadID = @FileUploadID
            AND FA.[StageID] = 17

        -- Log error details
        SET @ErrorNum = 50025;
        SET @ErrorMsg = [App].[ReturnErrorMessage](@ErrorNum);
        SET @errormessage = ERROR_MESSAGE()

        EXECUTE App.InsertErrorlogDetails
            @Errorprocedure = @Errorprocedure,
            @Errormessage = @Errormessage,
            @CorrelationID = @CorrelationID,
            @UserID = @UserID,
            @FileId = @FileId,
            @USERMESSAGE = @ErrorMsg
    END CATCH
END
GO
