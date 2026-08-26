/**********************************************************************************************
  Fortera Candescent Load - usp_Load_ODS_CANDESCENT.sql
  ---------------------------------------------------------------------------------------------
  Loads the daily Candescent CSV into DBase_Nook.dbo.ODS_CANDESCENT (TRUNCATE + reload), audited
  in DBase_Nook.dbo.FlatFileLoadLog.

  WHY THIS APPROACH:
    * The file has QUOTED business names with embedded commas -- "ATLAS MORTGAGE PARTNERS, LLC",
      "AUTO RESOLUTION GROUP, INC". Plain bcp (-t",") splits on every comma incl. those inside
      quotes, so those org rows fail with "Invalid character value for cast specification."
    * BULK INSERT FORMAT='CSV' would parse quotes, but the SQL engine reads the file as the service
      account and is DENIED on the \\...\d$ share (OS error 5). Only the xp_cmdshell/bcp context
      can read that share here.
    * So we stay in the xp_cmdshell context and pre-clean with PowerShell. NOTE: PowerShell on this
      host runs in CONSTRAINED LANGUAGE MODE (security policy) -- New-Object and .NET method calls
      like [System.IO.File]::WriteAllLines are blocked. This proc therefore uses ONLY cmdlets +
      operators: Import-Csv (a real quote-aware parser) -> ConvertTo-Csv (pipe-delimited) ->
      strip the wrapping quotes with -replace -> Set-Content.

  PRE-CLEAN OUTPUT: Candescent-clean.psv -- pipe-delimited, quotes stripped, UTF-8. ConvertTo-Csv
    emits a header row as line 1 (the UTF-8 BOM lands on it), so bcp skips line 1 with -F 2.

  SOURCE : \\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv
  CLEAN  : ...\Candescent-clean.psv   (regenerated each run)
  TARGET : DBase_Nook.dbo.ODS_CANDESCENT   (16 cols; file column order must match the table)
  Requires xp_cmdshell enabled and PowerShell on the SQL Server host.
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

        -- 1) Quote-aware pre-clean, Constrained-Language-Mode safe (cmdlets + operators only):
        --    Import-Csv parses quoted commas -> ConvertTo-Csv re-emits pipe-delimited (fields quoted)
        --    -> -replace strips the wrapping quotes -> Set-Content writes the file.
        DECLARE @ps NVARCHAR(4000) =
            'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
            'Import-Csv ''' + @src + ''' -Encoding UTF8 | ' +
            'ConvertTo-Csv -NoTypeInformation -Delimiter ''|'' | ' +
            'ForEach-Object { $_ -replace ([char]34),'''' } | ' +   -- [char]34 = " (avoids a literal quote that would unbalance cmd''s quoting)
            'Set-Content ''' + @clean + ''' -Encoding UTF8"';
        EXEC xp_cmdshell @ps, no_output;

        -- 2) bcp the clean pipe file. -F 2 skips the ConvertTo-Csv header (which also carries the BOM).
        --    Row terminator is LF (-r"\n"): safe whether the clean file is LF or CRLF -- a CRLF file
        --    just leaves a trailing CR on the last column, which the CHAR(13) strip below removes.
        DECLARE @cmd NVARCHAR(4000) =
            'bcp DBase_Nook.dbo.[ODS_CANDESCENT] in "' + @clean + '" ' +
            '-c -t"|" -r"\n" -F 2 -C 65001 -m 100000 -T -S pdhasqlvip01 ' +
            '-e "' + @err + '"';
        EXEC xp_cmdshell @cmd;

        -- Strip any trailing carriage return left on the last column when the file is CRLF
        UPDATE DBase_Nook.dbo.[ODS_CANDESCENT]
        SET AccountEstmtEnableCodeDescription = REPLACE(AccountEstmtEnableCodeDescription, CHAR(13), '')
        WHERE AccountEstmtEnableCodeDescription LIKE '%' + CHAR(13);

        -- Row count from the table (bcp runs out-of-process; @@ROWCOUNT won't reflect it)
        SET @rows    = (SELECT COUNT(*) FROM DBase_Nook.dbo.[ODS_CANDESCENT]);
        SET @EndTime = SYSDATETIME();
        SET @Message = CONCAT('Loaded ', @rows, ' rows (CLM-safe pipe-clean + bcp). Check CANDESCENT.err for any rejects.');

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
