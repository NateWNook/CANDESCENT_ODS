/**********************************************************************************************
  Create Table - DBase_Nook - ODS_CANDESCENT.sql
  ---------------------------------------------------------------------------------------------
  Landing table for the daily Candescent digital-banking extract. Lives in the DBase_Nook
  database (NOT a separate ODS_CANDESCENT database), named dbo.ODS_CANDESCENT. usp_DIM_DIGITAL_BANKING
  reads from this table. Column order matches the incoming Candescent-UserData.csv (bcp maps by
  position). Idempotent create.
**********************************************************************************************/
USE [DBase_Nook];
GO

IF OBJECT_ID('dbo.ODS_CANDESCENT','U') IS NULL
CREATE TABLE dbo.ODS_CANDESCENT (
    [NOOK_ID] int NULL,
    [FirstName] varchar(100) NULL,
    [LastName] varchar(100) NULL,
    [SSN] varchar(11) NULL,
    [EmailAddress] varchar(255) NULL,
    [RegisteredForOnlineBanking] char(1) NULL,
    [OnlineBankingRegistrationDateKey] int NULL,
    [ActiveOLBUser] char(1) NULL,
    [LastLoginDateKey] int NULL,
    [LastActivityDateKey] int NULL,
    [IsBillPayActivated] char(1) NULL,
    [BillPayEnrollmentDateKey] int NULL,
    [BillPayLastActivityDateKey] int NULL,
    [IsSMSBankingandAlertsEnrolled] char(1) NULL,
    [AccountEstmtEnableCodeDescription] varchar(20) NULL,
    [ProcessDate] int NULL
);
GO
