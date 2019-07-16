DECLARE @t nvarchar(max)

DECLARE cur CURSOR STATIC LOCAL FORWARD_ONLY 
FOR
WITH numbers AS (
	SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
	FROM sys.all_columns
)
,errorNumbers AS (
	SELECT n
	FROM numbers
	WHERE n BETWEEN 823 AND 825
)
,errorSeverities AS (
	SELECT n
	FROM numbers
	WHERE n BETWEEN 16 AND 25
)
SELECT 'EXEC msdb.dbo.sp_add_alert @name=N''Error Number '+ CAST(n AS varchar(10)) +''', 
		@message_id='+ CAST(n AS varchar(10)) +', 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=1 '
FROM errorNumbers

UNION ALL 

SELECT 'EXEC msdb.dbo.sp_add_notification @alert_name=N''Error Number '+ CAST(n AS varchar(10)) +''', @operator_name=N''DbAdmins'', @notification_method = 1'
FROM errorNumbers

UNION ALL

SELECT 'EXEC msdb.dbo.sp_add_alert @name=N''Severity '+ CAST(n AS varchar(10)) +''', 
		@message_id=0, 
		@severity='+ CAST(n AS varchar(10)) +', 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=1'
FROM errorSeverities

UNION ALL

SELECT 'EXEC msdb.dbo.sp_add_notification @alert_name=N''Severity '+ CAST(n AS varchar(10)) +''', @operator_name=N''DbAdmins'', @notification_method = 1'
FROM errorSeverities

OPEN cur

FETCH NEXT FROM cur INTO @t

WHILE @@FETCH_STATUS = 0
BEGIN 
	
	EXEC(@t)
	FETCH NEXT FROM cur INTO @t
END

CLOSE cur
DEALLOCATE cur