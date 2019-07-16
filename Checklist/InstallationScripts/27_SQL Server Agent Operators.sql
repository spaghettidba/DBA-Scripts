USE [msdb]
GO
EXEC msdb.dbo.sp_set_sqlagent_properties 
		@email_save_in_sent_folder=1, 
		@alert_replace_runtime_tokens=1, 
		@databasemail_profile=N'MailProfile', 
		@use_databasemail=1,
		@jobhistory_max_rows=10000

GO


IF NOT EXISTS (SELECT name FROM msdb.dbo.sysoperators WHERE name = N'DbAdmins')
EXEC msdb.dbo.sp_add_operator @name=N'DbAdmins', 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address=N'alerts@mycompany.com', 
		@category_name=N'[Uncategorized]'
GO

USE [msdb]
GO

EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator=N'DbAdmins', 
		@notificationmethod=0, 
		@forwardalways=0, 
		@pagersendsubjectonly=0, 
		@forwardingseverity=131, 
		@failsafeemailaddress=N'alerts@mycompany.com'
GO
