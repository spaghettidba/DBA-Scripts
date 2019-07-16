EXEC sp_configure 'Database Mail XPs', 1
RECONFIGURE WITH OVERRIDE;
GO

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'AccountRetryAttempts'
	,@parameter_value = N'1'
	,@description = N'Number of retry attempts for a mail server'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'AccountRetryDelay'
	,@parameter_value = N'60'
	,@description = N'Delay between each retry attempt to mail server'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'DatabaseMailExeMinimumLifeTime'
	,@parameter_value = N'600'
	,@description = N'Minimum process lifetime in seconds'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'DefaultAttachmentEncoding'
	,@parameter_value = N'MIME'
	,@description = N'Default attachment encoding'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'LoggingLevel'
	,@parameter_value = N'2'
	,@description = N'Database Mail logging level: normal - 1, extended - 2 (default), verbose - 3'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'MaxFileSize'
	,@parameter_value = N'1000000'
	,@description = N'Default maximum file size'

EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'ProhibitedExtensions'
	,@parameter_value = N'exe,dll,vbs,js'
	,@description = N'Extensions not allowed in outgoing mails'

GO

DECLARE @email_address sysname 
DECLARE @smtp_server sysname = N'smtp.mycompany.com'

SET @email_address = REPLACE(CAST(SERVERPROPERTY('ServerName') AS sysname) ,'\', '.')
SET @email_address = @email_address + '@mycompany.com'


IF NOT EXISTS (SELECT name FROM msdb.dbo.sysmail_account WHERE name = N'MailAccount')
BEGIN 
	EXEC msdb.dbo.sysmail_add_account_sp @account_name=N'MailAccount', 
		@email_address=@email_address
END 


EXEC msdb.dbo.sysmail_update_account_sp @account_name = N'MailAccount'
	,@description = N''
	,@email_address = @email_address
	,@display_name = N''
	,@replyto_address = N''
	,@mailserver_name = @smtp_server
	,@mailserver_type = N'SMTP'
	,@port = 25
	,@username = N''
	,@password = N''
	,@use_default_credentials = 0
	,@enable_ssl = 0

GO
IF NOT EXISTS (SELECT profile_id FROM msdb.dbo.sysmail_profile WHERE name = N'MailProfile')
BEGIN
	EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'MailProfile'

	EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'MailProfile'
		,@account_name = N'MailAccount'
		,@sequence_number = 1

	EXEC msdb.dbo.sysmail_add_principalprofile_sp @principal_name = N'guest'
		,@profile_name = N'MailProfile'
		,@is_default = 1

END
GO
