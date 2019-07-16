DECLARE @defaultLog nvarchar(4000)
DECLARE @sql nvarchar(max)

EXEC master.dbo.xp_instance_regread
	N'HKEY_LOCAL_MACHINE',
	N'Software\Microsoft\MSSQLServer\MSSQLServer',
	N'DefaultLog',
	@defaultLog OUTPUT

IF RIGHT(@defaultLog,1) <> '\'
	SET @defaultLog += '\'

DECLARE cur CURSOR STATIC LOCAL FORWARD_ONLY 
FOR
SELECT '
	ALTER DATABASE ' + QUOTENAME(DB_NAME(database_id)) + '
	MODIFY FILE (NAME = ' + name + ', FILENAME = ''' + @defaultLog + SUBSTRING(physical_name,LEN(physical_name) - CHARINDEX('\',REVERSE(physical_name)) + 2, LEN(physical_name))  + ''');'
FROM sys.master_files
WHERE db_name(database_id) IN ('master','model','msdb')
	AND type_desc = 'LOG'
	AND SUBSTRING(physical_name,1, LEN(physical_name) - CHARINDEX('\',REVERSE(physical_name)) + 1) <> @defaultLog


OPEN cur

FETCH NEXT FROM cur INTO @sql

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC(@sql)
	PRINT(@sql)
	
	FETCH NEXT FROM cur INTO @sql
END

CLOSE cur
DEALLOCATE cur