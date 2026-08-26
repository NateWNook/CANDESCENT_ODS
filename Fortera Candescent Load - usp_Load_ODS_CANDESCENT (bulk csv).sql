/**********************************************************************************************
  Fortera Candescent Load - usp_Load_ODS_CANDESCENT (bulk csv).sql
  ---------------------------------------------------------------------------------------------
  Loads the daily Candescent CSV into DBase_Nook.dbo.ODS_CANDESCENT (TRUNCATE + reload), audited
  in DBase_Nook.dbo.FlatFileLoadLog.

  WHY BULK INSERT (not bcp): the Candescent file contains QUOTED business names with embedded
  commas -- e.g. "ATLAS MORTGAGE PARTNERS, LLC", "AUTO RESOLUTION GROUP, INC". bcp -t"," is NOT a
  CSV parser: it splits on every comma including those inside quotes, shifting columns and throwing
  "Invalid character value for cast specification" on the org/LLC/INC rows. BULK INSERT with
  FORMAT='CSV', FIELDQUOTE='"' honors the quotes and loads those rows correctly.

  SOURCE : \\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv
  TARGET : DBase_Nook.dbo.ODS_CANDESCENT   (16 cols; file columns must be in this order)
  FORMAT : FORMAT='CSV' | FIELDQUOTE='"' | FIELDTERMINATOR=',' | ROWTERMINATOR=0x0a (LF) |
           FIRSTROW=2 (skip header) | CODEPAGE=65001 (UTF-8)

  ACCESS : BULK INSERT reads the file as the SQL Server *service* account (the same identity that
           bcp used under xp_cmdshell), over the proven FQDN d$ share. If it raises OS error 5/53
           (cannot open file), the service account lacks share access -- tell me and we'll pivot.
  NOTE   : xp_cmdshell is used only to clear the prior reject file before the load (BULK INSERT
           refuses to start if its ERRORFILE already exists).
**********************************************************************************************/
USE [DBase_Nook]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_Load_ODS_CANDESCENT]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME = SYSDATETIME();
    DECLARE @EndTime   DATETIME;
    DECLARE @Status    NVARCHAR(50)  = 'Success';
    DECLARE @Message   NVARCHAR(MAX) = NULL;
    DECLARE @rows      INT = 0;

    DECLARE @file NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv';
    DECLARE @err  NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\CANDESCENT_bulk.err';

    BEGIN TRY
        -- Log start
        INSERT INTO DBase_Nook.dbo.FlatFileLoadLog (ProcName, TableName, StartTime, Status)
        VALUES ('usp_Load_ODS_CANDESCENT', 'ODS_CANDESCENT', @StartTime, 'Started');

        -- Full refresh
        TRUNCATE TABLE DBase_Nook.dbo.[ODS_CANDESCENT];

        -- Clear any prior reject files (BULK INSERT will not start if the ERRORFILE exists)
        DECLARE @del NVARCHAR(1000) =
            'del "' + @err + '" "' + @err + '.Error.Txt" 2>nul';
        EXEC xp_cmdshell @del, no_output;

        -- Quote-aware CSV load
        BULK INSERT DBase_Nook.dbo.[ODS_CANDESCENT]
        FROM '\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv'
        WITH (
            FORMAT          = 'CSV',
            FIELDQUOTE      = '"',
            FIELDTERMINATOR = ',',
            ROWTERMINATOR   = '0x0a',      -- LF (matches the prior working bcp -r"\n"); use 0x0d0a if the file is CRLF
            FIRSTROW        = 2,           -- skip header
            CODEPAGE        = '65001',     -- UTF-8
            MAXERRORS       = 1000,        -- tolerate stragglers; rejects captured in ERRORFILE
            ERRORFILE       = '\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\CANDESCENT_bulk.err',
            TABLOCK
        );
        SET @rows = @@ROWCOUNT;

        SET @EndTime = SYSDATETIME();
        SET @Message = CONCAT('Loaded ', @rows, ' rows. Check CANDESCENT_bulk.err for any rejects.');

        -- Log success
        UPDATE DBase_Nook.dbo.FlatFileLoadLog
        SET EndTime = @EndTime, Status = @Status, Message = @Message
        WHERE ProcName = 'usp_Load_ODS_CANDESCENT' AND StartTime = @StartTime;

        SELECT rows_loaded = @rows;
    END TRY
    BEGIN CATCH
        SET @EndTime = SYSDATETIME();
        SET @Status  = 'Failed';
        SET @Message = ERROR_MESSAGE();

        -- Log failure
        UPDATE DBase_Nook.dbo.FlatFileLoadLog
        SET EndTime = @EndTime, Status = @Status, Message = @Message
        WHERE ProcName = 'usp_Load_ODS_CANDESCENT' AND StartTime = @StartTime;

        THROW;
    END CATCH
END;
GO

-- Run:
--   EXEC DBase_Nook.dbo.usp_Load_ODS_CANDESCENT;
--   SELECT COUNT(*) FROM DBase_Nook.dbo.ODS_CANDESCENT;
