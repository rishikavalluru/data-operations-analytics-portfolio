-- ============================================================================
-- O2C FRAUD TEST: Credit Limit Exceeded
-- ============================================================================
-- Test ID: O2CFMCA266
-- Business Rule: Customer account balance exceeds approved credit limit
-- Risk Level: HIGH
-- Impact: Credit risk exposure, potential bad debt, policy violation
-- ============================================================================

USE [O2C_FraudDetection]
GO

CREATE OR ALTER PROCEDURE [FraudTests].[O2CFMCA266_Credit_Limit_Exceeded]
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
        DECLARE @PatternID NVARCHAR(20) = 'O2CFMCA266'
        DECLARE @SOURCETABLENAME NVARCHAR(100) = 'Analytics.CustomerAccounts'
        DECLARE @AMOUNTFIELD NVARCHAR(100) = 'AccountBalance'

        -- ====================================================================
        -- SCHEMA VALIDATION - ADD TEST COLUMN
        -- ====================================================================
        
        IF NOT EXISTS (
            SELECT * FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA + '.' + TABLE_NAME = @SOURCETABLENAME
              AND COLUMN_NAME = @PatternID
        )
        BEGIN
            EXEC sp_executesql N'
                ALTER TABLE Analytics.CustomerAccounts
                ADD O2CFMCA266 NVARCHAR(10) NOT NULL DEFAULT(''False'')
            '
        END

        -- ====================================================================
        -- RESET FLAG
        -- ====================================================================
        
        UPDATE Analytics.CustomerAccounts
        SET O2CFMCA266 = 'False'
        WHERE O2CFMCA266 <> 'False'

        -- ====================================================================
        -- FRAUD DETECTION LOGIC
        -- ====================================================================
        -- Business Rule: Credit Exposure exceeds Credit Limit
        --
        -- This pattern indicates:
        --   - Credit policy violation
        --   - Risk of bad debt
        --   - Inadequate credit monitoring
        --   - Potential sales override of credit controls
        --
        -- Join to Credit Limit table and compare:
        --   - CreditExposure (current outstanding balance)
        --   - CreditLimit (approved maximum)
        -- ====================================================================
        
        UPDATE CA
        SET O2CFMCA266 = 'True'
        FROM Analytics.CustomerAccounts CA
        INNER JOIN Analytics.CustomerCreditLimit CCL
            ON CA.CustomerNumber = CCL.CustomerNumber
            AND CA.CompanyCode = CCL.CompanyCode
        WHERE CCL.CreditExposure > CCL.CreditLimit
          AND CCL.CreditLimit > 0

        -- ====================================================================
        -- METRICS CALCULATION
        -- ====================================================================
        
        DECLARE @HITS BIGINT, @RECORDS BIGINT, 
                @AMOUNT DECIMAL(38,5), @FAILUREAMOUNT DECIMAL(38,5)

        SELECT @HITS = COUNT(*) 
        FROM Analytics.CustomerAccounts 
        WHERE O2CFMCA266 = 'True'

        SELECT @RECORDS = COUNT(*) 
        FROM Analytics.CustomerAccounts

        SELECT @AMOUNT = SUM(AccountBalance) 
        FROM Analytics.CustomerAccounts

        SELECT @FAILUREAMOUNT = SUM(AccountBalance) 
        FROM Analytics.CustomerAccounts 
        WHERE O2CFMCA266 = 'True'

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
            RiskLevel = 'HIGH'
        WHERE TestID = @PatternID

        PRINT 'Test O2CFMCA266 completed: ' + CAST(@HITS AS VARCHAR) + ' findings'

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
