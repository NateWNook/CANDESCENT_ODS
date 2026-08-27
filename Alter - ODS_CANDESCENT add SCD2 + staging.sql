/**********************************************************************************************
  Alter - ODS_CANDESCENT add SCD2 + staging.sql   (DBase_Nook)
  ---------------------------------------------------------------------------------------------
  Turns dbo.ODS_CANDESCENT into an SCD Type 2 landing table (keeps history instead of truncate+reload)
  and creates the raw staging table the loader bcp's into.

    * Adds SCD2 columns: DATA_HASHBYTE, DATE_INSERTED, DATE_UPDATED, DATE_VALID_FROM, DATE_VALID_TO,
      FLAG_CURRENT, FLAG_DELETED.
    * Backfills existing rows as the initial CURRENT version (hash computed over the 14 business
      columns, EXCLUDING ProcessDate so a new file date alone is not treated as a change).
    * Creates dbo.ODS_CANDESCENT_STG (raw 15 columns only) as the bcp target.

  Run once before deploying the SCD2 version of usp_Load_ODS_CANDESCENT. Idempotent.
**********************************************************************************************/
USE [DBase_Nook];
GO

/*--- 1) SCD2 columns on ODS_CANDESCENT --------------------------------------------------------*/
IF COL_LENGTH('dbo.ODS_CANDESCENT','DATA_HASHBYTE')   IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD DATA_HASHBYTE   binary(32)   NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','DATE_INSERTED')   IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD DATE_INSERTED   datetime2(7) NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','DATE_UPDATED')    IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD DATE_UPDATED    datetime2(7) NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','DATE_VALID_FROM') IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD DATE_VALID_FROM date NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','DATE_VALID_TO')   IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD DATE_VALID_TO   date NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','FLAG_CURRENT')    IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD FLAG_CURRENT    char(1) NULL;
IF COL_LENGTH('dbo.ODS_CANDESCENT','FLAG_DELETED')    IS NULL ALTER TABLE dbo.ODS_CANDESCENT ADD FLAG_DELETED    char(1) NULL;
GO

/*--- 2) Backfill existing rows as the initial CURRENT version --------------------------------*/
UPDATE dbo.ODS_CANDESCENT
SET DATA_HASHBYTE = HASHBYTES('SHA2_256', CONCAT(
        FirstName,'|',LastName,'|',CONVERT(varchar(20),SSN),'|',EmailAddress,'|',
        RegisteredForOnlineBanking,'|',CONVERT(varchar(10),OnlineBankingRegistrationDateKey),'|',
        ActiveOLBUser,'|',CONVERT(varchar(10),LastLoginDateKey),'|',CONVERT(varchar(10),LastActivityDateKey),'|',
        IsBillPayActivated,'|',CONVERT(varchar(10),BillPayEnrollmentDateKey),'|',CONVERT(varchar(10),BillPayLastActivityDateKey),'|',
        IsSMSBankingandAlertsEnrolled,'|',AccountEstmtEnableCodeDescription)),
    DATE_INSERTED   = ISNULL(DATE_INSERTED, SYSDATETIME()),
    DATE_UPDATED    = ISNULL(DATE_UPDATED,  SYSDATETIME()),
    DATE_VALID_FROM = ISNULL(DATE_VALID_FROM, ISNULL(TRY_CONVERT(date, CAST(NULLIF(ProcessDate,0) AS char(8)),112), CAST(SYSDATETIME() AS date))),
    DATE_VALID_TO   = ISNULL(DATE_VALID_TO, '9999-12-31'),
    FLAG_CURRENT    = ISNULL(FLAG_CURRENT,'Y'),
    FLAG_DELETED    = ISNULL(FLAG_DELETED,'N')
WHERE DATA_HASHBYTE IS NULL OR FLAG_CURRENT IS NULL;
GO

/*--- 3) Raw staging table (bcp target; 15 business columns only, mirrors ODS_CANDESCENT) ------*/
IF OBJECT_ID('dbo.ODS_CANDESCENT_STG','U') IS NOT NULL DROP TABLE dbo.ODS_CANDESCENT_STG;
CREATE TABLE dbo.ODS_CANDESCENT_STG (
    [ProcessDate] int NULL,
    [FirstName] nvarchar(50) NULL,
    [LastName] nvarchar(50) NULL,
    [SSN] int NULL,
    [EmailAddress] nvarchar(50) NULL,
    [RegisteredForOnlineBanking] nvarchar(50) NULL,
    [OnlineBankingRegistrationDateKey] int NULL,
    [ActiveOLBUser] nvarchar(50) NULL,
    [LastLoginDateKey] int NULL,
    [LastActivityDateKey] int NULL,
    [IsBillPayActivated] nvarchar(50) NULL,
    [BillPayEnrollmentDateKey] int NULL,
    [BillPayLastActivityDateKey] int NULL,
    [IsSMSBankingandAlertsEnrolled] nvarchar(50) NULL,
    [AccountEstmtEnableCodeDescription] nvarchar(50) NULL
);
GO
