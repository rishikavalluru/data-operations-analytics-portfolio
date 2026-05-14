-- ============================================================================
-- P2P FRAUD TEST: Weekend/Holiday Processing Detection
-- ============================================================================
-- Test ID: P2PFMPO261
-- Business Rule: PO creation on weekends, holidays, or month-end periods
-- Risk Level: LOW-MEDIUM
-- Impact: Lack of oversight, off-hours fraud, unauthorized processing
-- ============================================================================

USE [P2P_FraudDetection]
GO

CREATE OR ALTER PROCEDURE [FraudTests].[P2PFMPO261_Weekend_Holiday]
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
        DECLARE @PatternID NVARCHAR(20) = 'P2PFMPO261'
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
                ADD P2PFMPO261 NVARCHAR(10) NOT NULL DEFAULT(''False''),
                    P2PFMPO261_HolidayOrWeekends NVARCHAR(255) NOT NULL DEFAULT(''Working Day'')
            '
        END

        -- ====================================================================
        -- RESET FLAGS
        -- ====================================================================
        
        UPDATE Analytics.PurchaseOrders
        SET P2PFMPO261 = 'False',
            P2PFMPO261_HolidayOrWeekends = 'Working Day'
        WHERE P2PFMPO261_HolidayOrWeekends <> 'Working Day' 
           OR P2PFMPO261 <> 'False'

        -- ====================================================================
        -- FRAUD DETECTION LOGIC
        -- ====================================================================
        -- Business Rule: POs created on non-working days
        --
        -- Flag POs where DocumentDate is:
        --   - Weekend (Saturday/Sunday)
        --   - Company holiday
        --   - Combination of both
        --
        -- This pattern indicates:
        --   - Off-hours processing without normal oversight
        --   - Potential unauthorized system access
        --   - Circumvention of approval processes
        -- ====================================================================
        
        ;WITH Holidays AS (
            SELECT * 
            FROM Reference.Holidays 
            WHERE IsArchived = 0
        ),
        Weekends AS (
            SELECT * 
            FROM Reference.Calendar
            WHERE IsWeekend = 1
        )
        UPDATE PO
        SET P2PFMPO261 = 'True',
            P2PFMPO261_HolidayOrWeekends = 
                CASE 
                    WHEN WK.IsWeekend = 1 AND Hld.[Holiday Name] IS NOT NULL 
                        THEN Hld.[Holiday Name] + ';' + WK.WeekDayName
                    WHEN WK.IsWeekend = 0 AND Hld.[Holiday Name] IS NOT NULL 
                        THEN Hld.[Holiday Name]
                    WHEN WK.IsWeekend = 1 AND Hld.[Holiday Name] IS NULL 
                        THEN WK.WeekDayName
                    ELSE Hld.[Holiday Name]
                END
        FROM Analytics.PurchaseOrders PO
        LEFT JOIN Holidays Hld
            ON CAST(PO.DocumentDate AS DATE) = Hld.HolidayDate
            AND PO.CompanyCode = Hld.CompanyCode
        LEFT JOIN Weekends WK
            ON CAST(PO.DocumentDate AS DATE) = WK.CalendarDate
        WHERE (WK.IsWeekend = 1 OR Hld.[Holiday Name] IS NOT NULL)

        -- ====================================================================
        -- METRICS CALCULATION
        -- ====================================================================
        
        DECLARE @HITS BIGINT, @RECORDS BIGINT, 
                @AMOUNT DECIMAL(38,5), @FAILUREAMOUNT DECIMAL(38,5)

        SELECT @HITS = COUNT(*) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PFMPO261 = 'True'

        SELECT @RECORDS = COUNT(*) 
        FROM Analytics.PurchaseOrders

        SELECT @AMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders

        SELECT @FAILUREAMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PFMPO261 = 'True'

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
            RiskLevel = CASE WHEN @FAILUREAMOUNT > 50000 THEN 'MEDIUM' 
                             ELSE 'LOW' END
        WHERE TestID = @PatternID

        PRINT 'Test P2PFMPO261 completed: ' + CAST(@HITS AS VARCHAR) + ' findings'

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
