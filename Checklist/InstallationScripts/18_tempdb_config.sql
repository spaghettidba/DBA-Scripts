
-- !!!!!!!!!!!!!!!!!!!   WARNING  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! --
-- 
--   RUN ONLY IF TEMPDB NOT CONFIGURED BY THE SETUP
-- 
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! --


USE [master]
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', SIZE = 100MB , FILEGROWTH = 100MB )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'templog', SIZE = 100MB , FILEGROWTH = 100MB )
GO



DECLARE @tempdbfiles int 

SELECT @tempdbfiles = MIN(tempdbfiles)
FROM (

	SELECT COUNT(*) tempdbfiles 
	FROM sys.dm_os_schedulers
	WHERE status = 'VISIBLE ONLINE'

	UNION ALL

	SELECT 8

) AS src;


PRINT @tempdbfiles 

DECLARE @physlocation varchar(255), @filecount int

SELECT @physlocation = MIN(physical_name) , @filecount = COUNT(*)  
FROM sys.master_files
WHERE database_id = DB_ID('tempdb')
AND type_desc = 'ROWS'


PRINT @filecount 


SET @physlocation = REPLACE(@physlocation, 'tempdb.mdf','')

DECLARE @sql nvarchar(max)

DECLARE c CURSOR 
FOR 
WITH Tally AS (
	SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS i
	FROM sys.all_columns
)
SELECT '
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N''tempdev_'+ CAST(i AS varchar(10)) +''', FILENAME = N'''+ @physlocation +'tempdb_'+ CAST(i AS varchar(10)) +'.ndf'' , SIZE = 100MB , FILEGROWTH = 100MB )
'
FROM Tally
WHERE i BETWEEN @filecount + 1 AND @tempdbfiles - @filecount + 1


OPEN c
FETCH NEXT FROM c INTO @sql

WHILE @@FETCH_STATUS = 0
BEGIN
	
	PRINT @sql
	EXEC(@sql)

	FETCH NEXT FROM c INTO @sql
END

CLOSE c
DEALLOCATE c