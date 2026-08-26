/**********************************************************************************************
  Fortera Candescent Load - Chained Jobs (ODS - DIM_DIGITAL_BANKING).sql   (create on 10.250.250.66)
  ---------------------------------------------------------------------------------------------
  Two chained jobs, run every morning at 10:00 AM:

     Fortera - Load ODS_CANDESCENT (daily)          [DAILY @ 10:00]
        step 1: EXEC DBase_Nook.dbo.usp_Load_ODS_CANDESCENT   (on success -> next step)
        step 2: sp_start_job 'Fortera - Load DIM_DIGITAL_BANKING (daily)'
     Fortera - Load DIM_DIGITAL_BANKING (daily)     [no schedule; started by the load job]
        step 1: EXEC DBase_Nook.dbo.usp_DIM_DIGITAL_BANKING

  Both steps are T-SQL (no CmdExec/PowerShell), so NO proxy is needed. All jobs owned by 'sa'.
  RUN THIS ENTIRE SCRIPT AS SYSADMIN (sa) in one execution -- the leading sp_delete_job lines must
  run so the recreate doesn't collide ("already exists"); non-sysadmins are denied on msdb.

  PREREQS: usp_Load_ODS_CANDESCENT and usp_DIM_DIGITAL_BANKING exist in DBase_Nook; xp_cmdshell
  enabled; DBase_Nook.dbo.ODS_CANDESCENT created; usp_DIM_DIGITAL_BANKING reads from that table.
**********************************************************************************************/
USE msdb;
GO

DECLARE @jobA sysname = N'Fortera - Load ODS_CANDESCENT (daily)';
DECLARE @jobB sysname = N'Fortera - Load DIM_DIGITAL_BANKING (daily)';
DECLARE @run_time int = 100000;   -- 10:00:00 (HHMMSS)

-- Clean slate
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobA) EXEC msdb.dbo.sp_delete_job @job_name = @jobA;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobB) EXEC msdb.dbo.sp_delete_job @job_name = @jobB;

/*--- Job B: DIM_DIGITAL_BANKING (started by the load job) -----------------------------------*/
EXEC msdb.dbo.sp_add_job @job_name = @jobB, @enabled = 1, @owner_login_name = N'sa',
     @description = N'Rebuild DIM_DIGITAL_BANKING from DBase_Nook.dbo.ODS_CANDESCENT. Triggered by the Candescent load job.';
EXEC msdb.dbo.sp_add_jobstep @job_name = @jobB, @step_id = 1, @step_name = N'Load DIM_DIGITAL_BANKING',
     @subsystem = N'TSQL', @database_name = N'DBase_Nook', @command = N'EXEC dbo.usp_DIM_DIGITAL_BANKING;',
     @on_success_action = 1, @on_fail_action = 2, @retry_attempts = 1, @retry_interval = 5;
EXEC msdb.dbo.sp_add_jobserver @job_name = @jobB;

/*--- Job A: Load ODS_CANDESCENT (DAILY @ 10:00), then start Job B ----------------------------*/
EXEC msdb.dbo.sp_add_job @job_name = @jobA, @enabled = 1, @owner_login_name = N'sa',
     @description = N'Load DBase_Nook.dbo.ODS_CANDESCENT from the Candescent CSV (bcp), then start DIM_DIGITAL_BANKING.';
EXEC msdb.dbo.sp_add_jobstep @job_name = @jobA, @step_id = 1, @step_name = N'Load ODS_CANDESCENT',
     @subsystem = N'TSQL', @database_name = N'DBase_Nook', @command = N'EXEC dbo.usp_Load_ODS_CANDESCENT;',
     @on_success_action = 3, @on_fail_action = 2, @retry_attempts = 1, @retry_interval = 5;
EXEC msdb.dbo.sp_add_jobstep @job_name = @jobA, @step_id = 2, @step_name = N'Start DIM_DIGITAL_BANKING load',
     @subsystem = N'TSQL', @database_name = N'msdb',
     @command = N'EXEC msdb.dbo.sp_start_job @job_name = N''Fortera - Load DIM_DIGITAL_BANKING (daily)'';',
     @on_success_action = 1, @on_fail_action = 2;
EXEC msdb.dbo.sp_add_jobserver @job_name = @jobA;
EXEC msdb.dbo.sp_add_jobschedule @job_name = @jobA, @name = N'Daily 10am',
     @freq_type = 4, @freq_interval = 1, @active_start_time = @run_time;
GO
