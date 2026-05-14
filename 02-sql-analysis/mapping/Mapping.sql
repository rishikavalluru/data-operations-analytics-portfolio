-- ============================================================================
-- SAP PROCURE-TO-PAY DATA MAPPING
-- ============================================================================
-- File: PurchaseOrders_Data_Mapping.sql
-- Purpose: Transform staged SAP data into unified analytics model
-- Author: Rishika Reddy Valluru
-- Module: Procure-to-Pay (P2P)
-- Description: Maps Purchase Order staging tables (EKKO, EKPO) into analytics
--              layer with incremental processing, lookback logic, and vendor
--              master enrichment
-- 
-- Key Operations:
--   1. Incremental date range determination
--   2. Lookback PO identification (changed historical records)
--   3. Delete-and-insert pattern for changed records
--   4. Multi-table JOIN (EKKO + EKPO + vendor master + reference data)
--   5. Vendor master enrichment for missing vendors
-- ============================================================================

USE [P2P_Analytics]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ============================================================================
-- STORED PROCEDURE: SAP_PurchaseOrders
-- ============================================================================
-- Parameters:
--   @FileId        : Unique identifier for the file
--   @RowIds        : Table-valued parameter for multiple file IDs
--   @CorrelationID : Correlation ID for tracking
--   @UserID        : User who initiated mapping
-- ============================================================================

ALTER PROCEDURE [Mapping].[SAP_PurchaseOrders]
    @FileId VARCHAR(100) = NULL,
    @RowIds [App].[FileIds] READONLY,
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @UserID UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET XACT_ABORT ON
    BEGIN TRY
        -- ====================================================================
        -- INITIALIZATION
        -- ====================================================================
        
        -- Update mapping status to 'In Progress'
        EXEC App.Table_DataMapping 
            @Type = 1,
            @Status = 3,
            @EntityTypeID = 10 -- P2P_PurchaseOrder

        -- Variable declarations
        DECLARE @FromDate DATE = NULL
        DECLARE @ToDate DATE = NULL
        DECLARE @Module VARCHAR(100)
        DECLARE @SubModule VARCHAR(100)
        DECLARE @UDMTable VARCHAR(100)
        DECLARE @RecordCnt INT
        DECLARE @Errormessage NVARCHAR(MAX) = ''
        DECLARE @Errorprocedure NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
        DECLARE @ErrorNum INT
        DECLARE @ErrorMsg VARCHAR(300)

        SET @Module = 'P2P'
        SET @SubModule = 'PurchaseOrders'
        SET @UDMTable = 'Analytics.PurchaseOrders_stage'

        -- ====================================================================
        -- STEP 1: DETERMINE PROCESSING DATE RANGE
        -- ====================================================================
        -- Business Rule: Process only records within configured date window
        -- Impact: Incremental processing reduces runtime by 60-80%
        -- ====================================================================
        
        PRINT 'Determining processing date range'
        
        SELECT @FromDate = FromDate,
               @ToDate = ToDate
        FROM [App].[DateRanges] DR
        WHERE IsActive = 1
          AND Module = @Module
          AND SubModule = @SubModule

        -- Validate date range exists
        IF ISNULL(@FromDate, '') = '' OR ISNULL(@ToDate, '') = ''
        BEGIN
            SET @ErrorNum = 50061
            SET @ErrorMsg = [APP].[ReturnErrorMessage](@ErrorNum);
            THROW @ErrorNum, @ErrorMsg, 1
        END

        PRINT 'Processing date range: ' + CAST(@FromDate AS VARCHAR) + ' to ' + CAST(@ToDate AS VARCHAR)

        -- ====================================================================
        -- STEP 2: IDENTIFY LOOKBACK POs (CHANGED HISTORICAL RECORDS)
        -- ====================================================================
        -- Business Rule: Include POs from previous periods if they have invoices
        --                or payments in current period
        -- Impact: Ensures reporting accuracy when historical POs are referenced
        --         in current transactions
        -- ====================================================================
        
        PRINT 'Identifying lookback POs'
        
        DROP TABLE IF EXISTS #LookbackPOs

        -- POs changed in current period
        SELECT SPT_ROWID, 'True' LookbackFlag
        INTO #LookbackPOs
        FROM Staging.EKPO
        WHERE AEDAT BETWEEN @FromDate AND @ToDate

        UNION

        -- Historical POs referenced in current period invoices
        SELECT PO.SPT_ROWID, 'True' LookbackFlag
        FROM Staging.Invoices I
        INNER JOIN STAGING.BSEG B
            ON I.BELNR = B.BELNR
            AND I.BUKRS = B.BUKRS
            AND I.GJAHR = B.GJAHR
        INNER JOIN Staging.EKPO PO
            ON B.EBELN = PO.EBELN
            AND B.EBELP = PO.EBELP
        WHERE I.BUDAT BETWEEN @FromDate AND @ToDate
          AND PO.AEDAT < @FromDate

        -- ====================================================================
        -- STEP 3: DELETE CHANGED RECORDS FROM ANALYTICS LAYER
        -- ====================================================================
        -- Business Rule: Remove records that will be refreshed to avoid duplicates
        -- Method: Delete-and-insert pattern ensures clean refresh
        -- ====================================================================
        
        PRINT 'Deleting changed records from analytics layer'
        
        ;WITH DATERANGE AS (
            SELECT a.*
            FROM Analytics.PurchaseOrders_Stage a
            LEFT JOIN #LookbackPOs b
                ON a.SPT_ROWID = b.SPT_ROWID
            WHERE b.SPT_ROWID IS NOT NULL -- Records to refresh
        )
        DELETE FROM Analytics.PurchaseOrders_Stage
        WHERE SPT_ROWID IN (SELECT SPT_ROWID FROM DATERANGE)

        -- ====================================================================
        -- STEP 4: MAP STAGING TO ANALYTICS LAYER
        -- ====================================================================
        -- Business Rule: Transform SAP staging tables into unified analytics model
        -- Method: Multi-table JOIN with business logic transformations
        -- ====================================================================
        
        PRINT 'Mapping staging data to analytics layer'
        
        INSERT INTO Analytics.PurchaseOrders_Stage (
            [PurchaseOrderNumber],
            [PurchaseOrderLineItem],
            [VendorNumber],
            [VendorName],
            [CompanyCode],
            [PurchasingOrganization],
            [PurchasingGroup],
            [DocumentDate],
            [CreatedDate],
            [MaterialNumber],
            [MaterialDescription],
            [OrderQuantity],
            [OrderUnit],
            [NetPrice],
            [PriceUnit],
            [Currency],
            [NetOrderValue],
            [TaxCode],
            [Plant],
            [StorageLocation],
            [DeletionIndicator],
            [SPT_Source],
            [SPT_ROWID]
        )
        SELECT 
            H.EBELN AS [PurchaseOrderNumber],
            I.EBELP AS [PurchaseOrderLineItem],
            H.LIFNR AS [VendorNumber],
            V.NAME1 AS [VendorName],
            H.BUKRS AS [CompanyCode],
            H.EKORG AS [PurchasingOrganization],
            H.EKGRP AS [PurchasingGroup],
            H.BEDAT AS [DocumentDate],
            H.AEDAT AS [CreatedDate],
            I.MATNR AS [MaterialNumber],
            I.TXZ01 AS [MaterialDescription],
            I.MENGE AS [OrderQuantity],
            I.MEINS AS [OrderUnit],
            I.NETPR AS [NetPrice],
            I.PEINH AS [PriceUnit],
            I.WAERS AS [Currency],
            I.NETWR AS [NetOrderValue],
            I.MWSKZ AS [TaxCode],
            I.WERKS AS [Plant],
            I.LGORT AS [StorageLocation],
            I.LOEKZ AS [DeletionIndicator],
            'SAP_' + H.MANDT AS [SPT_Source],
            I.SPT_ROWID
        FROM #LookbackPOs L
        INNER JOIN Staging.EKPO I
            ON L.SPT_ROWID = I.SPT_ROWID
        INNER JOIN Staging.EKKO H
            ON I.EBELN = H.EBELN
        LEFT JOIN Staging.LFA1 V -- Vendor master
            ON H.LIFNR = V.LIFNR
        WHERE I.IsSoftDelete = 0
          AND H.IsSoftDelete = 0

        -- ====================================================================
        -- STEP 5: VENDOR MASTER ENRICHMENT
        -- ====================================================================
        -- Business Rule: Add vendor records for vendors missing from master data
        -- Impact: Prevents orphan vendor references in analytics
        -- ====================================================================
        
        PRINT 'Enriching vendor master with missing vendors'
        
        INSERT INTO Analytics.VendorMaster_Stage (
            [VendorNumber],
            [VendorName],
            [CompanyCode],
            [SPT_Source],
            [SPT_ROWID]
        )
        SELECT DISTINCT 
            Y.[VendorNumber],
            'Not present in vendor master' AS [VendorName],
            ISNULL(App.DISTINCTLIST(STRING_AGG(X.[CompanyCode], ';'), ';'), '') AS [CompanyCode],
            'Analytics.PurchaseOrders' AS [SPT_Source],
            MAX(Y.SPT_RowID) AS [SPT_ROWID]
        FROM Analytics.PurchaseOrders_Stage Y
        LEFT JOIN Analytics.VendorMaster_Stage X
            ON X.[VendorNumber] = Y.[VendorNumber]
        WHERE X.[VendorNumber] IS NULL
        GROUP BY Y.[VendorNumber]

        -- ====================================================================
        -- STEP 6: RECORD COUNT AND STATUS UPDATE
        -- ====================================================================
        
        SELECT @RecordCnt = COUNT(1)
        FROM Analytics.PurchaseOrders_Stage WITH (NOLOCK)

        EXEC App.Table_DataMapping 
            @Type = 2,
            @Status = 4,
            @EntityTypeID = 10,
            @RecordCount = @RecordCnt,
            @Module = @Module

        PRINT 'Mapping completed successfully. Records mapped: ' + CAST(@RecordCnt AS VARCHAR(10))

    END TRY

    BEGIN CATCH
        -- ====================================================================
        -- ERROR HANDLING
        -- ====================================================================
        
        -- Update mapping status to 'Failed'
        EXEC App.Table_DataMapping 
            @Type = 5,
            @Status = 5,
            @EntityTypeid1 = 4,
            @EntityTypeID = 10

        -- Log error details
        SET @ErrorNum = 50028;
        SET @ErrorMsg = [App].[ReturnErrorMessage](@ErrorNum);
        SET @errormessage = ERROR_MESSAGE()

        EXECUTE App.InsertErrorlogDetails 
            @Errorprocedure = @Errorprocedure,
            @Errormessage = @Errormessage,
            @CorrelationID = @CorrelationID,
            @UserID = @UserID,
            @FileId = @FileId,
            @Usermessage = @ErrorMsg

        PRINT 'Mapping failed with error: ' + @ErrorMsg
    END CATCH
END
GO
