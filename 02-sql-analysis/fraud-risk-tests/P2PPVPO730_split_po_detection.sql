-- ============================================================================
-- P2P FRAUD TEST: Split PO Detection
-- ============================================================================
-- Test ID: P2PPVPO730
-- Business Rule: Identifies POs with identical Material, Vendor, Plant, Price,
--                and Date which may indicate PO splitting to avoid thresholds
-- Risk Level: MEDIUM-HIGH
-- Impact: Threshold circumvention, unauthorized spending
-- ============================================================================

USE [P2P_FraudDetection]
GO

CREATE OR ALTER PROCEDURE [FraudTests].[P2PPVPO730_SplitPO_Detection]
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
        DECLARE @PatternID NVARCHAR(20) = 'P2PPVPO730'
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
                ADD P2PPVPO730 NVARCHAR(10) NOT NULL DEFAULT(''False''),
                    P2PPVPO730_Grd INT NOT NULL DEFAULT(0)
            '
        END

        -- ====================================================================
        -- RESET FLAGS
        -- ====================================================================
        
        UPDATE Analytics.PurchaseOrders
        SET P2PPVPO730 = 'False',
            P2PPVPO730_Grd = 0
        WHERE P2PPVPO730 <> 'False' OR P2PPVPO730_Grd <> 0

        -- ====================================================================
        -- FRAUD DETECTION LOGIC
        -- ====================================================================
        -- Business Rule: Multiple POs with identical:
        --   - Material Code (same item being ordered)
        --   - Vendor Number (same supplier)
        --   - Plant (same location)
        --   - Price Per Unit (same rate)
        --   - Changed On Date (same day/time)
        --
        -- This pattern indicates potential PO splitting to stay below
        -- approval thresholds while ordering from same vendor
        -- ====================================================================
        
        ;WITH SplitPOs AS (
            SELECT DISTINCT 
                PO.MaterialCode,
                PO.VendorNumber,
                PO.Plant,
                PO.VendorCurrency,
                PO.PricePerUnit,
                PO.ChangedOn,
                PO.SPT_ROWID,
                -- Group matching POs together for reporting
                DENSE_RANK() OVER (
                    ORDER BY PO.MaterialCode, PO.Plant, PO.ChangedOn, 
                             PO.VendorNumber, PO.VendorCurrency, PO.PricePerUnit
                ) AS GroupRank
            FROM Analytics.PurchaseOrders PO
            INNER JOIN Analytics.PurchaseOrders PO1
                ON PO.MaterialCode = PO1.MaterialCode
                AND PO.Plant = PO1.Plant
                AND PO.ChangedOn = PO1.ChangedOn
                AND PO.VendorNumber = PO1.VendorNumber
                AND PO.VendorCurrency = PO1.VendorCurrency
                AND PO.PricePerUnit = PO1.PricePerUnit
            WHERE PO.SPT_ROWID <> PO1.SPT_ROWID -- Different records
              AND PO.PONumber <> PO1.PONumber -- Different PO numbers
              AND ISNULL(PO.VendorNumber, '') <> ''
              AND ISNULL(PO.Plant, '') <> ''
              AND ISNULL(PO.MaterialCode, '') <> ''
        )
        UPDATE PO
        SET P2PPVPO730 = 'True',
            P2PPVPO730_Grd = S.GroupRank
        FROM Analytics.PurchaseOrders PO
        INNER JOIN SplitPOs S
            ON PO.SPT_ROWID = S.SPT_ROWID

        -- ====================================================================
        -- METRICS CALCULATION
        -- ====================================================================
        
        DECLARE @HITS BIGINT, @RECORDS BIGINT, 
                @AMOUNT DECIMAL(38,5), @FAILUREAMOUNT DECIMAL(38,5)

        SELECT @HITS = COUNT(*) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PPVPO730 = 'True'

        SELECT @RECORDS = COUNT(*) 
        FROM Analytics.PurchaseOrders

        SELECT @AMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders

        SELECT @FAILUREAMOUNT = SUM(NetOrderValue) 
        FROM Analytics.PurchaseOrders 
        WHERE P2PPVPO730 = 'True'

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
            RiskLevel = CASE WHEN @FAILUREAMOUNT > 100000 THEN 'HIGH' 
                             ELSE 'MEDIUM' END
        WHERE TestID = @PatternID

        PRINT 'Test P2PPVPO730 completed: ' + CAST(@HITS AS VARCHAR) + ' findings'

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
