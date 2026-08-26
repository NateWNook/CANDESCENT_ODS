/**********************************************************************************************
  Fortera Candescent Load - usp_Load_ODS_CANDESCENT (bcp).sql
  ---------------------------------------------------------------------------------------------
  Loads the daily Candescent CSV into DBase_Nook.dbo.ODS_CANDESCENT (TRUNCATE + bcp), same pattern
  as the Velera loader: xp_cmdshell + bcp, over the proven FQDN d$ share, -S pdhasqlvip01 -T,
  audited in DBase_Nook.dbo.FlatFileLoadLog. (Date keys stay as int here and are converted
  downstream in usp_DIM_DIGITAL_BANKING.)

  SOURCE : \\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv
  TARGET : DBase_Nook.dbo.ODS_CANDESCENT   (16 cols; the file's columns must be in this order)
  bcp    : -c char | -t"," comma | -r"\n" LF rows | -F 2 skip header | -C 65001 UTF-8 | -T | -S pdhasqlvip01
  Requires xp_cmdshell enabled (as the Symitar/Velera loads already use it).
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

    BEGIN TRY
        -- Log start
        INSERT INTO DBase_Nook.dbo.FlatFileLoadLog (ProcName, TableName, StartTime, Status)
        VALUES ('usp_Load_ODS_CANDESCENT', 'ODS_CANDESCENT', @StartTime, 'Started');

        -- Full refresh
        EXEC('TRUNCATE TABLE DBase_Nook.dbo.[ODS_CANDESCENT]');

        -- bcp import (reads over the proven FQDN d$ share)
        DECLARE @cmd NVARCHAR(4000) =
            'bcp DBase_Nook.dbo.[ODS_CANDESCENT] in ' +
            '"\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv" ' +
            '-c -t"," -r"\n" -F 2 -C 65001 -T -S pdhasqlvip01 ' +
            '-e "\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\CANDESCENT.err"';
        EXEC xp_cmdshell @cmd;

        SET @EndTime = SYSDATETIME();

        -- Log success
        UPDATE DBase_Nook.dbo.FlatFileLoadLog
        SET EndTime = @EndTime, Status = @Status
        WHERE ProcName = 'usp_Load_ODS_CANDESCENT' AND StartTime = @StartTime;
    END TRY
    BEGIN CATCH
        SET @EndTime = SYSDATETIME();
        SET @Status  = 'Failed';
        SET @Message = ERROR_MESSAGE();

        -- Log failure
        UPDATE DBase_Nook.dbo.FlatFileLoadLog
        SET EndTime = @EndTime, Status = @Status, Message = @Message
        WHERE ProcName = 'usp_Load_ODS_CANDESCENT' AND StartTime = @StartTime;
    END CATCH
END;
GO

-- Run:
--   EXEC DBase_Nook.dbo.usp_Load_ODS_CANDESCENT;
--   SELECT TOP 20 * FROM DBase_Nook.dbo.ODS_CANDESCENT;
