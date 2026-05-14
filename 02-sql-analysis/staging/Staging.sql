-- ============================================================================
-- SAP PROCURE-TO-PAY STAGING PROCESS
-- ============================================================================
-- Purpose: Transform raw SAP Purchase Order Line Items (EKPO) data into 
--          staging table for downstream processing
-- Author: Rishika Reddy Valluru
-- Module: Procure-to-Pay (P2P)
-- Description: Performs data staging operations including schema validation,
--              duplicate handling, dynamic column mapping, and incremental
--              load processing from raw to staging layer
-- 
-- Key Operations:
--   1. Schema validation and column addition
--   2. Duplicate detection and soft-delete marking
--   3. Dynamic column list generation
--   4. Upsert logic (insert new, update existing records)
--   5. Audit trail maintenance
-- ============================================================================

USE [P2P_DataStaging]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- STORED PROCEDURE: SAP_EKPO
-- ============================================================================
-- Parameters:
--   @TableName     : Name of the raw data table (source)
--   @TableType     : Template type identifier ('EKPO')
--   @FileId        : Unique identifier for the uploaded file
--   @CorrelationID : Correlation ID for cross-process tracking
--   @UserID        : User who initiated the staging process
-- ============================================================================

ALTER PROCEDURE [Staging].[SAP_EKPO] (
    @TableName VARCHAR(100),
    @TableType VARCHAR(50),
    @FileId VARCHAR(100),
    @CorrelationID UNIQUEIDENTIFIER,
    @UserID UNIQUEIDENTIFIER
)
AS
BEGIN
    BEGIN TRY
        -- ====================================================================
        -- INITIALIZATION
        -- ====================================================================
        
        -- Update staging status to 'In Progress'
        EXEC App.Template_DataStaging
            @Type = 1,
            @Status_1 = 3,
            @EntityTypeID_1 = 4,
            @TableName = @TableName,
            @FileId = @FileId,
            @TableType = @TableType

        -- Variable declarations
        DECLARE @RawColmList VARCHAR(MAX)
        DECLARE @StrSQL NVARCHAR(MAX)
        DECLARE @SQL NVARCHAR(MAX)
        DECLARE @SPT_Source VARCHAR(100)
        DECLARE @TotalCnt INT
        DECLARE @Start INT = 1
        DECLARE @Count INT
        DECLARE @ErrorMessage NVARCHAR(4000)
        DECLARE @ErrorSeverity INT
        DECLARE @ErrorState INT
        DECLARE @FileUploadID INT
        DECLARE @ColumnList NVARCHAR(MAX)
        DECLARE @SQLStr NVARCHAR(MAX)
        DECLARE @Errorprocedure NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @ErrorNum INT
        DECLARE @ErrorMsg VARCHAR(300)
        DECLARE @updatestaging NVARCHAR(MAX)
        DECLARE @insertstaginglist NVARCHAR(MAX)
        DECLARE @selectrawlist NVARCHAR(MAX)
        DECLARE @DateValidationTable NVARCHAR(100) = '[DQC].[DateValidations'
        DECLARE @ID NVARCHAR(100)

        -- ====================================================================
        -- STEP 1: SCHEMA VALIDATION - ADD MANDT COLUMN IF MISSING
        -- ====================================================================
        -- Business Rule: MANDT (Client ID) is a required key field in SAP tables
        -- Impact: Without MANDT, records cannot be properly partitioned by client
        -- ====================================================================
        
        IF NOT EXISTS (
            SELECT 1 
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = '' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''),
                                              CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) + 1,
                                              LEN(REPLACE(REPLACE(@TableName, '[', ''), ']', ''))) + ''
              AND TABLE_SCHEMA = '' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''), 1,
                                                CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) - 1) + ''
              AND COLUMN_NAME = 'MANDT'
        )
        BEGIN
            PRINT 'Adding MANDT column to raw table'
            SET @SQL = 'ALTER TABLE ' + @TABLENAME + ' ADD MANDT NVARCHAR(10)'
            EXEC (@SQL)
        END

        -- ====================================================================
        -- STEP 2: DUPLICATE DETECTION AND SOFT DELETE MARKING
        -- ====================================================================
        -- Business Rule: Only the first occurrence of duplicate keys should be processed
        -- Method: Uses ROW_NUMBER() to identify duplicates and marks them as soft-deleted
        -- Impact: Prevents duplicate data from propagating to staging and analytics layers
        -- ====================================================================
        
        PRINT 'Marking duplicate records as soft-deleted'
        
        SET @SQL = '
            ;WITH RowCTE AS (
                SELECT SPT_ROWID, IsSoftDelete,
                    ROW_NUMBER() OVER(PARTITION BY MANDT, EBELN, EBELP
                                      ORDER BY SPT_ROWID) AS RANK_A
                FROM ' + @TableName + '
            )
            UPDATE RowCTE
            SET IsSoftDelete = 1
            WHERE RANK_A > 1
        ';
        EXEC sys.sp_executesql @SQL;

        -- ====================================================================
        -- STEP 3: DYNAMIC COLUMN LIST GENERATION
        -- ====================================================================
        -- Purpose: Builds column lists dynamically to handle varying schemas
        -- Lists Generated:
        --   1. @updatestaging   : SET clause for UPDATE statement
        --   2. @insertstaginglist : Column list for INSERT statement
        --   3. @selectrawlist    : SELECT clause from raw table
        -- ====================================================================
        
        PRINT 'Building dynamic column lists for staging operations'
        
        -- Generate UPDATE column list
        SET @StrSQL = '
            SELECT @updatestaging = STUFF((
                SELECT '', '' + ''s.['' + B.COLUMN_NAME + ''] '' + ''='' + ''t.['' + B.COLUMN_NAME + ''] ''
                FROM INFORMATION_SCHEMA.COLUMNS A
                INNER JOIN INFORMATION_SCHEMA.COLUMNS B
                    ON A.Column_Name = B.Column_Name
                    AND A.Table_Name = ''EKPO''
                    AND A.Table_Schema = ''Staging''
                WHERE B.TABLE_NAME = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''),
                                                     CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) + 1,
                                                     LEN(REPLACE(REPLACE(@TableName, '[', ''), ']', ''))) + '''
                  AND B.TABLE_SCHEMA = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''), 1,
                                                       CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) - 1) + '''
                  AND A.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'', ''IsSoftDelete'')
                  AND B.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'', ''IsSoftDelete'')
                  AND b.COLUMN_NAME <> ''IsSoftDelete''
                FOR XML PATH('''')
            ), 1, 1, '''')
        ';
        EXEC sys.sp_executesql @StrSQL, N'@updatestaging NVARCHAR(MAX) OUTPUT', @updatestaging = @updatestaging OUTPUT

        -- Add source ID mapping to update list
        SET @updatestaging = CONCAT(@updatestaging, ', s.SPT_SourceID = t.SPT_RowId');

        -- Generate INSERT column list
        SET @StrSQL = '
            SELECT @insertstaginglist = STUFF((
                SELECT '', '' + ''a.['' + B.COLUMN_NAME + ''] ''
                FROM INFORMATION_SCHEMA.COLUMNS A
                INNER JOIN INFORMATION_SCHEMA.COLUMNS B
                    ON A.Column_Name = B.Column_Name
                    AND A.Table_Name = ''EKPO''
                    AND A.Table_Schema = ''Staging''
                WHERE B.TABLE_NAME = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''),
                                                     CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) + 1,
                                                     LEN(REPLACE(REPLACE(@TableName, '[', ''), ']', ''))) + '''
                  AND B.TABLE_SCHEMA = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''), 1,
                                                       CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) - 1) + '''
                  AND A.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'')
                  AND B.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'')
                FOR XML PATH('''')
            ), 1, 1, '''')
        ';
        EXEC sys.sp_executesql @StrSQL, N'@insertstaginglist NVARCHAR(MAX) OUTPUT', @insertstaginglist = @insertstaginglist OUTPUT

        -- Generate SELECT column list from raw table
        SET @StrSQL = '
            SELECT @selectrawlist = STUFF((
                SELECT '', '' + ''t.['' + B.COLUMN_NAME + ''] ''
                FROM INFORMATION_SCHEMA.COLUMNS A
                INNER JOIN INFORMATION_SCHEMA.COLUMNS B
                    ON A.Column_Name = B.Column_Name
                    AND A.Table_Name = ''EKPO''
                    AND A.Table_Schema = ''Staging''
                WHERE B.TABLE_NAME = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''),
                                                     CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) + 1,
                                                     LEN(REPLACE(REPLACE(@TableName, '[', ''), ']', ''))) + '''
                  AND B.TABLE_SCHEMA = ''' + SUBSTRING(REPLACE(REPLACE(@TableName, '[', ''), ']', ''), 1,
                                                       CHARINDEX('.', REPLACE(REPLACE(@TableName, '[', ''), ']', '')) - 1) + '''
                  AND A.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'')
                  AND B.COLUMN_NAME NOT IN (''SPT_ROWID'', ''ProjectId'')
                FOR XML PATH('''')
            ), 1, 1, '''')
        ';
        EXEC sys.sp_executesql @StrSQL, N'@selectrawlist NVARCHAR(MAX) OUTPUT', @selectrawlist = @selectrawlist OUTPUT

        -- ====================================================================
        -- STEP 4: UPDATE EXISTING RECORDS IN STAGING
        -- ====================================================================
        -- Business Rule: Update staging records when matching keys exist in raw data
        -- Method: Matches on MANDT + EBELN + EBELP composite key
        -- Impact: Ensures staging reflects most recent data from source
        -- ====================================================================
        
        PRINT 'Updating existing records in staging table'
        
        SET @StrSQL = '
            UPDATE s
            SET ' + @updatestaging + '
            FROM staging.EKPO s
            INNER JOIN ' + @TableName + ' T
                ON T.MANDT = s.MANDT
                AND T.EBELN = S.EBELN
                AND T.EBELP = S.EBELP
            WHERE ISNULL(T.IsSoftDelete, 0) <> 1
        '
        EXEC sys.sp_executesql @StrSQL;

        -- ====================================================================
        -- STEP 5: INSERT NEW RECORDS INTO STAGING
        -- ====================================================================
        -- Business Rule: Insert records from raw that don't exist in staging
        -- Method: LEFT JOIN with NULL check to identify new records
        -- Impact: Incremental load - only processes new data
        -- ====================================================================
        
        PRINT 'Inserting new records into staging table'
        
        SET @StrSQL = '
            INSERT INTO staging.EKPO (' + @insertstaginglist + ')
            SELECT ' + @selectrawlist + '
            FROM ' + @TableName + ' T
            LEFT JOIN staging.EKPO s
                ON T.MANDT = s.MANDT
                AND T.EBELN = S.EBELN
                AND T.EBELP = S.EBELP
            WHERE s.MANDT IS NULL 
              AND s.EBELN IS NULL 
              AND S.EBELP IS NULL
              AND ISNULL(T.IsSoftDelete, 0) <> 1
        '
        EXEC sys.sp_executesql @StrSQL;

        -- ====================================================================
        -- STEP 6: RECORD COUNT AND STATUS UPDATE
        -- ====================================================================
        
        -- Get count of staged records
        DECLARE @Module VARCHAR(100)
        DECLARE @SubModule VARCHAR(100)
        DECLARE @FromDate DATE = NULL
        DECLARE @ToDate DATE = NULL

        SET @Module = 'P2P'
        SET @SubModule = 'Invoices'

        -- Get date range for processing window
        SELECT @FromDate = FromDate, @ToDate = ToDate
        FROM [App].[DateRanges] DR
        WHERE IsActive = 1
          AND Module = @Module
          AND SubModule = @SubModule

        -- Extract source system identifier
        SET @StrSQL = 'SELECT @SPT_Source = SPT_Source FROM ' + @TableName
        EXEC sys.sp_executesql @StrSQL, N'@SPT_Source VARCHAR(100) OUTPUT', @SPT_Source = @SPT_Source OUTPUT

        -- Count staged records
        SET @StrSQL = '
            SELECT @Count = COUNT(1)
            FROM [Staging].[EKPO] WITH (NOLOCK)
            WHERE SPT_Source = ''' + @SPT_Source + '''
        '
        EXEC sys.sp_executesql @StrSQL, N'@Count INT OUTPUT', @Count = @Count OUTPUT

        -- Update staging status to 'Completed'
        EXEC App.Template_DataStaging
            @Type = 4,
            @Status_1 = 4,
            @Record_count = @count,
            @EntityTypeID_1 = 4,
            @TableName = @TableName,
            @FileId = @FileId,
            @TableType = @TableType,
            @UDMTable = 'Analytics.Purchaseorders',
            @SourceERPTemplate_name = 'EKPO'

        -- Trigger downstream mapping process
        EXEC App.MappingUpdate EKPO
        EXEC App.ProcessingUpdate

        -- Get file upload ID for audit
        SELECT @FileUploadID = FileUploadID
        FROM DM.File_Details(NOLOCK)
        WHERE RowID = @FileId
          AND isActive = 1

        -- Update entity status
        EXEC App.Template_DataStaging
            @Type = 2,
            @EntityName = 'Staging',
            @SourceERPTemplate_name = 'EKPO',
            @entitytypeid_4 = 20,
            @Status_2 = 4,
            @StagingExclCount = 0

        -- Update audit trail
        UPDATE [APP].[FileAudit]
        SET [ModifiedOn] = GETUTCDATE()
        FROM [APP].[FileAudit]
        WHERE FileUploadID = @FileUploadID
          AND StageID = 18

        PRINT 'Staging completed successfully. Records processed: ' + CAST(@Count AS VARCHAR(10))

    END TRY

    BEGIN CATCH
        -- ====================================================================
        -- ERROR HANDLING
        -- ====================================================================
        
        -- Update staging status to 'Failed'
        EXEC App.Template_DataStaging 
            @Type = 3,
            @TableName = @TableName,
            @FileId = @FileId,
            @TableType = @TableType,
            @Status_3 = 5,
            @EntityTypeID_2 = 2,
            @EntityTypeID_3 = 4

        -- Update audit trail
        UPDATE [APP].[FileAudit]
        SET [ModifiedOn] = GETUTCDATE()
        FROM [APP].[FileAudit]
        WHERE FileUploadID = @FileUploadID
          AND StageID = 18

        -- Log error details
        SET @ErrorNum = 50027;
        SET @ErrorMsg = [App].[ReturnErrorMessage](@ErrorNum);
        SET @errormessage = ERROR_MESSAGE()

        EXECUTE App.InsertErrorlogDetails 
            @Errorprocedure = @Errorprocedure,
            @Errormessage = @Errormessage,
            @CorrelationID = @CorrelationID,
            @UserID = @UserID,
            @FileId = @FileId,
            @Usermessage = @ErrorMsg

        PRINT 'Staging failed with error: ' + @ErrorMsg
    END CATCH
END
GO

-- ============================================================================
-- USAGE EXAMPLE
-- ============================================================================
/*
EXEC [Staging].[SAP_EKPO]
    @TableName = '[Raw].[P2PSAPEKPO_20260512]',
    @TableType = 'EKPO',
    @FileId = '41 64D0F7-626C-4EE6-A432-6C39CF6F4461',
    @CorrelationID = NEWID(),
    @UserID = 'A1234567-89AB-CDEF-0123-456789ABCDEF'
*/

-- ============================================================================
-- PROCESS FLOW
-- ============================================================================
-- 1. Schema Validation     → Ensures MANDT column exists
-- 2. Duplicate Detection   → Marks duplicates as soft-deleted
-- 3. Column List Generation → Builds dynamic SQL for varying schemas
-- 4. Update Existing       → Updates matching records in staging
-- 5. Insert New            → Adds new records to staging
-- 6. Audit & Status Update → Updates processing metrics and audit trail
-- ============================================================================
