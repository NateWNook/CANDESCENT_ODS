/**********************************************************************************************
  ETL_Candescent_to_DIM_DIGITAL_BANKING.sql
  ---------------------------------------------------------------------------------------------
  Loads digital-banking data from the Candescent ODS into the warehouse dimension.

    SOURCE : DBase_Nook.dbo.ODS_CANDESCENT
    TARGET : DBASE_NOOK.dbo.DIM_DIGITAL_BANKING
    XREF   : DBASE_NOOK.dbo.DIM_NOOK_CONTACT  (SSN -> NOOK_ID)

  RULES
    * NOOK_ID is resolved from DIM_NOOK_CONTACT by matching SSN (NOT the source's own NOOK_ID).
    * Assumption: any SSN present in Candescent already exists in DIM_NOOK_CONTACT (populated
      from the core). Rows whose SSN is NOT found in DIM_NOOK_CONTACT are EXCLUDED from the load.
    * SSN is normalized (dashes/spaces stripped) on both sides before matching, so formatting
      differences (e.g. '127-04-6677' vs '127046677') do not cause false misses.
    * Source *DateKey / ProcessDate (yyyymmdd int) columns are converted to real DATE values.
    * ONE ROW PER NOOK_ID: source rows are aggregated by NOOK_ID with tiebreakers --
      'Y' wins for every Y/N flag, MAX for every date, 'Enrolled' wins for estatement_enrollment_status.
      (Supersedes the earlier SELECT DISTINCT, which only collapsed fully-identical rows.)
    * Full refresh: the target is truncated and reloaded each run.
**********************************************************************************************/
USE DBASE_NOOK;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DIM_DIGITAL_BANKING
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @src int, @loaded int, @excluded int;

    SELECT @src = COUNT(*) FROM DBase_Nook.dbo.ODS_CANDESCENT;

    BEGIN TRAN;

    TRUNCATE TABLE dbo.DIM_DIGITAL_BANKING;

    -- Aggregate the source to exactly ONE ROW PER NOOK_ID with the survivorship rules.
    ;WITH agg AS (
        SELECT
            n.NOOK_ID,
            -- Y/N flags: 'Y' wins (MAX over {'Y','N'} returns 'Y' whenever any row is 'Y')
            MAX(CASE WHEN UPPER(LTRIM(RTRIM(c.RegisteredForOnlineBanking))) IN ('Y','1','TRUE') THEN 'Y'
                     WHEN UPPER(LTRIM(RTRIM(c.RegisteredForOnlineBanking))) IN ('N','0','FALSE') THEN 'N' END) AS online_banking_registered,
            MAX(TRY_CONVERT(date, CAST(NULLIF(c.OnlineBankingRegistrationDateKey, 0) AS char(8)), 112)) AS online_banking_registration_date,
            MAX(CASE WHEN UPPER(LTRIM(RTRIM(c.ActiveOLBUser))) IN ('Y','1','TRUE') THEN 'Y'
                     WHEN UPPER(LTRIM(RTRIM(c.ActiveOLBUser))) IN ('N','0','FALSE') THEN 'N' END) AS active_user,
            MAX(TRY_CONVERT(date, CAST(NULLIF(c.LastLoginDateKey, 0) AS char(8)), 112)) AS last_login_date,
            MAX(TRY_CONVERT(date, CAST(NULLIF(c.LastActivityDateKey, 0) AS char(8)), 112)) AS last_activity_date,
            MAX(CASE WHEN UPPER(LTRIM(RTRIM(c.IsBillPayActivated))) IN ('Y','1','TRUE') THEN 'Y'
                     WHEN UPPER(LTRIM(RTRIM(c.IsBillPayActivated))) IN ('N','0','FALSE') THEN 'N' END) AS bill_pay_activated,
            MAX(TRY_CONVERT(date, CAST(NULLIF(c.BillPayEnrollmentDateKey, 0) AS char(8)), 112)) AS bill_pay_enrollment_date,
            MAX(TRY_CONVERT(date, CAST(NULLIF(c.BillPayLastActivityDateKey, 0) AS char(8)), 112)) AS bill_pay_last_activity_date,
            MAX(CASE WHEN UPPER(LTRIM(RTRIM(c.IsSMSBankingandAlertsEnrolled))) IN ('Y','1','TRUE') THEN 'Y'
                     WHEN UPPER(LTRIM(RTRIM(c.IsSMSBankingandAlertsEnrolled))) IN ('N','0','FALSE') THEN 'N' END) AS sms_alerts_enrolled,
            -- e-statement: 'Enrolled' wins if ANY row is Enrolled
            CASE WHEN SUM(CASE WHEN UPPER(LTRIM(RTRIM(c.AccountEstmtEnableCodeDescription))) = 'ENROLLED' THEN 1 ELSE 0 END) > 0
                 THEN 'Enrolled' ELSE MAX(LTRIM(RTRIM(c.AccountEstmtEnableCodeDescription))) END AS estatement_enrollment_status,
            MAX(c.ProcessDate) AS process_date_key      -- latest file/process date for this member
        FROM DBase_Nook.dbo.ODS_CANDESCENT c
        INNER JOIN DBASE_NOOK.dbo.DIM_NOOK_CONTACT n
            ON REPLACE(REPLACE(c.SSN, '-', ''), ' ', '') = REPLACE(REPLACE(n.SSN, '-', ''), ' ', '')
        GROUP BY n.NOOK_ID
    )
    INSERT dbo.DIM_DIGITAL_BANKING
        (NOOK_ID, online_banking_registered, online_banking_registration_date, active_user,
         last_login_date, last_activity_date, bill_pay_activated, bill_pay_enrollment_date,
         bill_pay_last_activity_date, sms_alerts_enrolled, estatement_enrollment_status,
         DATE_DATA, DATA_HASHBYTE, DATE_INSERTED, DATE_UPDATED, DATE_DELETED,
         DATE_VALID_FROM, DATE_VALID_TO, FLAG_CURRENT, FLAG_DELETED)
    SELECT
         a.NOOK_ID, a.online_banking_registered, a.online_banking_registration_date, a.active_user,
         a.last_login_date, a.last_activity_date, a.bill_pay_activated, a.bill_pay_enrollment_date,
         a.bill_pay_last_activity_date, a.sms_alerts_enrolled, a.estatement_enrollment_status,
         TRY_CONVERT(date, CAST(NULLIF(a.process_date_key, 0) AS char(8)), 112),   -- DATE_DATA (latest ODS process date)
         HASHBYTES('SHA2_256', CONCAT(                                             -- DATA_HASHBYTE (change detection)
                CONVERT(varchar(10), a.NOOK_ID), '|',
                a.online_banking_registered, '|',
                CONVERT(varchar(10), a.online_banking_registration_date, 112), '|',
                a.active_user, '|',
                CONVERT(varchar(10), a.last_login_date, 112), '|',
                CONVERT(varchar(10), a.last_activity_date, 112), '|',
                a.bill_pay_activated, '|',
                CONVERT(varchar(10), a.bill_pay_enrollment_date, 112), '|',
                CONVERT(varchar(10), a.bill_pay_last_activity_date, 112), '|',
                a.sms_alerts_enrolled, '|',
                a.estatement_enrollment_status)),
         TRY_CONVERT(date, CAST(NULLIF(a.process_date_key, 0) AS char(8)), 112),   -- DATE_INSERTED
         TRY_CONVERT(date, CAST(NULLIF(a.process_date_key, 0) AS char(8)), 112),   -- DATE_UPDATED
         NULL,                                                                     -- DATE_DELETED
         TRY_CONVERT(date, CAST(NULLIF(a.process_date_key, 0) AS char(8)), 112),   -- DATE_VALID_FROM
         '9999-12-31',                                                             -- DATE_VALID_TO
         'Y',                                                                      -- FLAG_CURRENT
         'N'                                                                       -- FLAG_DELETED
    FROM agg a;

    SET @loaded = @@ROWCOUNT;
    COMMIT;

    SET @excluded = @src - @loaded;
    SELECT source_rows = @src,
           loaded_rows = @loaded,
           excluded_no_ssn_match = @excluded;
END
GO

-- Run it:
--   EXEC dbo.usp_DIM_DIGITAL_BANKING;
