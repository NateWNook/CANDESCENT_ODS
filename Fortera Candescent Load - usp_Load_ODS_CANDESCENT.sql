/**********************************************************************************************
  Fortera Candescent Load - usp_Load_ODS_CANDESCENT.sql
  ---------------------------------------------------------------------------------------------
  Loads the daily Candescent CSV into DBase_Nook.dbo.ODS_CANDESCENT (TRUNCATE + reload), audited
  in DBase_Nook.dbo.FlatFileLoadLog.

  WHY THIS APPROACH:
    * The file contains QUOTED business names with embedded commas -- "ATLAS MORTGAGE PARTNERS,
      LLC", "AUTO RESOLUTION GROUP, INC", etc. Plain bcp (-t",") is not a CSV parser: it splits on
      every comma including those inside quotes, so those org rows fail with "Invalid character
      value for cast specification."
    * BULK INSERT with FORMAT='CSV' *would* parse quotes correctly, but the SQL engine reads the
      file as the service account and is DENIED on the \\...\d$ share (OS error 5) -- only the
      xp_cmdshell/bcp context can read that share here.
    * Solution: stay in the xp_cmdshell context. Use PowerShell's Import-Csv (a real quote-aware
      parser) to re-emit the file as PIPE-delimited, header-less, no-BOM UTF-8, then bcp that.

  SOURCE : \\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv
  CLEAN  : ...\Candescent-clean.psv   (regenerated each run; pipe-delimited, no quotes, no header)
  TARGET : DBase_Nook.dbo.ODS_CANDESCENT   (16 cols; file column order must match the table)
  Requires xp_cmdshell enabled (as the Symitar/Velera loads already use it) and PowerShell on the
  SQL Server host.
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

    DECLARE @src   NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv';
    DECLARE @clean NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv';
    DECLARE @err   NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\CANDESCENT.err';

    BEGIN TRY
        -- Log start
        INSERT INTO DBase_Nook.dbo.FlatFileLoadLog (ProcName, TableName, StartTime, Status)
        VALUES ('usp_Load_ODS_CANDESCENT', 'ODS_CANDESCENT', @StartTime, 'Started');

        -- Full refresh
        TRUNCATE TABLE DBase_Nook.dbo.[ODS_CANDESCENT];

        -- 1) Quote-aware pre-clean via PowerShell (runs in the xp_cmdshell context that CAN read d$).
        --    Import-Csv parses quoted commas correctly; re-emit pipe-delimited, header-less, no-BOM UTF-8.
        DECLARE @ps NVARCHAR(4000) =
            'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
            '$enc=New-Object System.Text.UTF8Encoding($false); ' +
            '$lines=Import-Csv ''' + @src + ''' | ForEach-Object { ($_.PSObject.Properties.Value) -join ''|'' }; ' +
            '[System.IO.File]::WriteAllLines(''' + @clean + ''',$lines,$enc)"';
        EXEC xp_cmdshell @ps, no_output;

        -- 2) bcp the clean pipe file. No -F (no header). WriteAllLines uses CRLF -> -r"\r\n".
        DECLARE @cmd NVARCHAR(4000) =
            'bcp DBase_Nook.dbo.[ODS_CANDESCENT] in "' + @clean + '" ' +
            '-c -t"|" -r"\r\n" -C 65001 -m 100000 -T -S pdhasqlvip01 ' +
            '-e "' + @err + '"';
        EXEC xp_cmdshell @cmd;

        -- Row count comes from the table (bcp runs out-of-process, so @@ROWCOUNT won't reflect it)
        SET @rows    = (SELECT COUNT(*) FROM DBase_Nook.dbo.[ODS_CANDESCENT]);
        SET @EndTime = SYSDATETIME();
        SET @Message = CONCAT('Loaded ', @rows, ' rows (pipe-clean + bcp). Check CANDESCENT.err for any rejects.');

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
