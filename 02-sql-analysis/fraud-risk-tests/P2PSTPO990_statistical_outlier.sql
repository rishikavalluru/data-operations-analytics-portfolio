-- ============================================================================
-- P2P FRAUD TEST: Statistical Outlier Detection
-- ============================================================================
-- Test ID: P2PSTPO990
-- Business Rule: PO values that differ significantly from average order value
--                for a vendor (beyond statistical thresholds)
-- Risk Level: MEDIUM
-- Impact: Anomalous transactions, data entry errors, potential fraud
-- ============================================================================

USE [P2P_FraudDetection]
GO

CREATE OR ALTER PROCEDURE [FraudTests].[P2PSTPO990_Statistical_Outlier]
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
        DECLARE @PatternID NVARCHAR(20) = 'P2PSTPO990'
        DECLARE @SOURCETABLENAME NVARCHAR(100) = 'Analytics.PurchaseOrders'
        DECLARE @AMOUNTFIELD NVARCHAR(100) = 'NetOrderValue'
        DECLARE @THRESHOLD_STDDEV DECIMAL(5,2) = 3.0 -- 3 standard deviations

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
                ADD P2PSTPO990 NVARCHAR(10) NOT NULL DEFAULT(''False''),
                    P2PSTPO990_Min_Threshold MONEY NOT NULL DEFAULT(0),
                    P2PSTPO990_Max_Threshold MONEY NOT NULL DEFAULT(0)
            '
        END

        -- ====================================================================
        -- RESET FLAGS
        -- ====================================================================
        
        UPDATE Analytics.PurchaseOrders
        SET P2PSTPO990 = 'False',
            P2PSTPO990_Max_Threshold = 0,
            P2PSTPO990_Min_Threshold = 0

        -- ====================================================================
        -- FRAUD DETECTION LOGIC
        -- ====================================================================
        -- Statistical Method: Z-Score Analysis
        --
        -- For each vendor, calculate:
        --   - Average (mean) PO amount
        --   - Standard deviation of PO amounts
        --
        -- Flag POs where amount is:
        --   > (Average + 3 * StdDev)  OR
        --   < (Average - 3 * StdDev)
        --
        -- This identifies statistical outliers that warrant investigation
        -- ====================================================================
        
        -- Calculate vendor-level statistics
        SELECT VendorNumber,
               AVG(NetOrderValue) AS [Average],
               STDEV(NetOrderValue) AS [StandardDeviation]
        INTO #VendorStats
        FROM Analytics.PurchaseOrders PO
        WHERE NetOrderValue > 0
        GROUP BY VendorNumber
        HAVING COUNT(*) >= 3 -- Need at least 3 transactions for meaningful stats

        -- Flag outliers
        UPDATE PO
        SET P2PSTPO990 = 'True',
            P2PSTPO990_Max_Threshold = VS.[Average] + (@THRESHOLD_STDDEV * VS.[StandardDeviation]),
            P2PSTPO990_Min_Threshold = VS.[Average] - (@THRESHOLD_STDDEV * VS.[StandardDeviation])
        FROM Analytics.PurchaseOrders PO
        INNER JOIN #VendorStats VS
            ON PO.VendorNumber = VS.VendorNumber
        WHERE (PO.NetOrderValue > VS.[Average] + (@THRESHOLD_STDDEV * VS.[StandardDeviation])
            OR PO.NetOrderValue < VS.[Average] - (@THRESHOLD_STDDEV * VS.[StandardDeviation]))

        DROP TABLE #VendorStats

        -- ====================================================================
        -- METRICS CALCULATION
        -- ====================================================================
        
        DECLARE @HITS BIGINT, @RECORDS BIGINT, 
                @AMOUNT DECIMAL(38,5), @FAILUREAMOUNT DECIMAL(38,5)

        SELECT @HITS = COUNT(*) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PSTPO990 = 'True'

        SELECT @RECORDS = COUNT(*) 
        FROM Analytics.PurchaseOrders

        SELECT @AMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders

        SELECT @FAILUREAMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PSTPO990 = 'True'

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

        PRINT 'Test P2PSTPO990 completed: ' + CAST(@HITS AS VARCHAR) + ' findings'

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
