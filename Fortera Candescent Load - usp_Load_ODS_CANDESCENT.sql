/**********************************************************************************************
  Fortera Candescent Load - usp_Load_ODS_CANDESCENT.sql   (SCD Type 2)
  ---------------------------------------------------------------------------------------------
  Loads the daily Candescent CSV into DBase_Nook.dbo.ODS_CANDESCENT while KEEPING HISTORY.
  Prereq: run "Alter - ODS_CANDESCENT add SCD2 + staging.sql" first (adds SCD2 columns + the
  dbo.ODS_CANDESCENT_STG staging table).

  FLOW:
    1) TRUNCATE the raw staging table dbo.ODS_CANDESCENT_STG.
    2) Quote-aware pre-clean (PowerShell Import-Csv, Constrained-Language-Mode safe) + bcp the
       clean pipe file INTO THE STAGING TABLE (not the ODS table).
    3) SCD2 merge staging -> ODS_CANDESCENT, keyed on a full-row hash that EXCLUDES ProcessDate:
         * rows no longer present in the file  -> expire (FLAG_CURRENT='N', FLAG_DELETED='Y', VALID_TO=@now)
         * new/changed rows (hash not current) -> insert a new CURRENT version
         * unchanged rows                      -> left as-is (history retained)

  SOURCE : \\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv
  Audited in DBase_Nook.dbo.FlatFileLoadLog. Requires xp_cmdshell + PowerShell on the SQL host.
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
    DECLARE @staged INT = 0, @expired INT = 0, @inserted INT = 0;

    DECLARE @src   NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv';
    DECLARE @clean NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv';
    DECLARE @err   NVARCHAR(400) = N'\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\CANDESCENT.err';

    BEGIN TRY
        INSERT INTO DBase_Nook.dbo.FlatFileLoadLog (ProcName, TableName, StartTime, Status)
        VALUES ('usp_Load_ODS_CANDESCENT', 'ODS_CANDESCENT', @StartTime, 'Started');

        -- 1) clear the raw staging table
        TRUNCATE TABLE DBase_Nook.dbo.[ODS_CANDESCENT_STG];

        -- 2) quote-aware pre-clean (CLM-safe) -> pipe file
        DECLARE @ps NVARCHAR(4000) =
            'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
            'Import-Csv ''' + @src + ''' -Encoding UTF8 | ' +
            'ConvertTo-Csv -NoTypeInformation -Delimiter ''|'' | ' +
            'ForEach-Object { $_ -replace ([char]34),'''' } | ' +
            'Set-Content ''' + @clean + ''' -Encoding UTF8"';
        EXEC xp_cmdshell @ps, no_output;

        --    bcp the clean pipe file INTO STAGING (-F 2 skips the ConvertTo-Csv header)
        DECLARE @cmd NVARCHAR(4000) =
            'bcp DBase_Nook.dbo.[ODS_CANDESCENT_STG] in "' + @clean + '" ' +
            '-c -t"|" -r"\n" -F 2 -C 65001 -m 100000 -T -S pdhasqlvip01 ' +
            '-e "' + @err + '"';
        EXEC xp_cmdshell @cmd;

        -- strip any trailing CR left on the last column when the file is CRLF
        UPDATE DBase_Nook.dbo.[ODS_CANDESCENT_STG]
        SET AccountEstmtEnableCodeDescription = REPLACE(AccountEstmtEnableCodeDescription, CHAR(13), '')
        WHERE AccountEstmtEnableCodeDescription LIKE '%' + CHAR(13);

        -- 3) hash the staged rows (exclude ProcessDate) and SCD2-merge into ODS_CANDESCENT
        IF OBJECT_ID('tempdb..#stg') IS NOT NULL DROP TABLE #stg;
        SELECT *,
            HASHBYTES('SHA2_256', CONCAT(
                FirstName,'|',LastName,'|',CONVERT(varchar(20),SSN),'|',EmailAddress,'|',
                RegisteredForOnlineBanking,'|',CONVERT(varchar(10),OnlineBankingRegistrationDateKey),'|',
                ActiveOLBUser,'|',CONVERT(varchar(10),LastLoginDateKey),'|',CONVERT(varchar(10),LastActivityDateKey),'|',
                IsBillPayActivated,'|',CONVERT(varchar(10),BillPayEnrollmentDateKey),'|',CONVERT(varchar(10),BillPayLastActivityDateKey),'|',
                IsSMSBankingandAlertsEnrolled,'|',AccountEstmtEnableCodeDescription)) AS HB
        INTO #stg
        FROM DBase_Nook.dbo.[ODS_CANDESCENT_STG];
        SET @staged = @@ROWCOUNT;

        DECLARE @now date = ISNULL((SELECT MAX(TRY_CONVERT(date, CAST(NULLIF(ProcessDate,0) AS char(8)),112)) FROM #stg),
                                   CAST(SYSDATETIME() AS date));

        BEGIN TRAN;

        -- expire current rows that are no longer present in the new file
        UPDATE t
        SET FLAG_CURRENT='N', FLAG_DELETED='Y', DATE_VALID_TO=@now, DATE_UPDATED=SYSDATETIME()
        FROM DBase_Nook.dbo.ODS_CANDESCENT t
        WHERE t.FLAG_CURRENT='Y'
          AND NOT EXISTS (SELECT 1 FROM #stg s WHERE s.HB = t.DATA_HASHBYTE);
        SET @expired = @@ROWCOUNT;

        -- insert new/changed distinct rows as the new CURRENT version
        INSERT DBase_Nook.dbo.ODS_CANDESCENT
            (ProcessDate, FirstName, LastName, SSN, EmailAddress, RegisteredForOnlineBanking,
             OnlineBankingRegistrationDateKey, ActiveOLBUser, LastLoginDateKey, LastActivityDateKey,
             IsBillPayActivated, BillPayEnrollmentDateKey, BillPayLastActivityDateKey,
             IsSMSBankingandAlertsEnrolled, AccountEstmtEnableCodeDescription,
             DATA_HASHBYTE, DATE_INSERTED, DATE_UPDATED, DATE_VALID_FROM, DATE_VALID_TO, FLAG_CURRENT, FLAG_DELETED)
        SELECT
             s.ProcessDate, s.FirstName, s.LastName, s.SSN, s.EmailAddress, s.RegisteredForOnlineBanking,
             s.OnlineBankingRegistrationDateKey, s.ActiveOLBUser, s.LastLoginDateKey, s.LastActivityDateKey,
             s.IsBillPayActivated, s.BillPayEnrollmentDateKey, s.BillPayLastActivityDateKey,
             s.IsSMSBankingandAlertsEnrolled, s.AccountEstmtEnableCodeDescription,
             s.HB, SYSDATETIME(), SYSDATETIME(), @now, '9999-12-31', 'Y', 'N'
        FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY HB ORDER BY (SELECT NULL)) AS rn
              FROM #stg) s
        WHERE s.rn = 1
          AND NOT EXISTS (SELECT 1 FROM DBase_Nook.dbo.ODS_CANDESCENT t
                          WHERE t.DATA_HASHBYTE = s.HB AND t.FLAG_CURRENT = 'Y');
        SET @inserted = @@ROWCOUNT;

        COMMIT;

        SET @EndTime = SYSDATETIME();
        SET @Message = CONCAT('Staged ', @staged, ' | new/changed versions inserted ', @inserted,
                              ' | expired (dropped from file) ', @expired, '. Check CANDESCENT.err for rejects.');

        UPDATE DBase_Nook.dbo.FlatFileLoadLog
        SET EndTime = @EndTime, Status = @Status, Message = @Message
        WHERE ProcName = 'usp_Load_ODS_CANDESCENT' AND StartTime = @StartTime;

        SELECT staged_rows=@staged, versions_inserted=@inserted, versions_expired=@expired;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
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
--   SELECT * FROM DBase_Nook.dbo.ODS_CANDESCENT WHERE FLAG_CURRENT='Y';   -- current snapshot
