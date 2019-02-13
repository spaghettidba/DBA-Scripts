/*
 * LoginAudit2008.sql
 * --------------------------------------
 * Records in a histogram target the count 
 * of all statements executed by database
 * and by user
 */

IF EXISTS (
    SELECT 1 
    FROM sys.server_event_sessions 
    WHERE name = 'loginaudit'
)
DROP EVENT SESSION [loginaudit] ON SERVER;

CREATE EVENT SESSION loginaudit ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.username)
)
ADD TARGET package0.asynchronous_bucketizer(SET slots = 64, filtering_event_name=N'sqlserver.sql_statement_completed',source=N'sqlserver.username',source_type=(1))
GO


IF EXISTS (
    SELECT 1 
    FROM sys.server_event_sessions 
    WHERE name = 'loginaudit2'
)
DROP EVENT SESSION [loginaudit2] ON SERVER;

CREATE EVENT SESSION loginaudit2 ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.database_id)
)
ADD TARGET package0.asynchronous_bucketizer(SET slots = 64, filtering_event_name=N'sqlserver.sql_statement_completed',source=N'sqlserver.database_id',source_type=(1))
GO



ALTER EVENT SESSION loginaudit 
ON SERVER
STATE=START



ALTER EVENT SESSION loginaudit2
ON SERVER
STATE=START



SELECT 
    'UserName' AS object_type,
    n.value('(value)[1]', 'sysname') AS ObjectName,
    n.value('(@count)[1]', 'int') AS EventCount,
    n.value('(@trunc)[1]', 'int') AS EventsTrunc
FROM
(SELECT CAST(target_data as XML) target_data
FROM sys.dm_xe_sessions AS s 
JOIN sys.dm_xe_session_targets t
    ON s.address = t.event_session_address
WHERE s.name = 'loginaudit'
  AND t.target_name = 'asynchronous_bucketizer') as tab
CROSS APPLY target_data.nodes('BucketizerTarget/Slot') as q(n)


UNION ALL

SELECT 
    'DatabaseName' AS object_type,
    DB_NAME(n.value('(value)[1]', 'int')) AS DatabaseName,
    n.value('(@count)[1]', 'int') AS EventCount,
    n.value('(@trunc)[1]', 'int') AS EventsTrunc
FROM
(SELECT CAST(target_data as XML) target_data
FROM sys.dm_xe_sessions AS s 
JOIN sys.dm_xe_session_targets t
    ON s.address = t.event_session_address
WHERE s.name = 'loginaudit2'
  AND t.target_name = 'asynchronous_bucketizer') as tab
CROSS APPLY target_data.nodes('BucketizerTarget/Slot') as q(n)