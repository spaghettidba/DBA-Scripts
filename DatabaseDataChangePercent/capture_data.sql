USE [msdb]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 
-- This function cracks the output from a DBCC PAGE dump
-- of an allocation bitmap. It takes a string in the form
-- "(1:8) - (1:16)" or "(1:8) -" and returns the number
-- of extents represented by the string. Both the examples
-- above equal 1 extent.
--
CREATE FUNCTION [dbo].[DBAConvertToExtents] (
    @extents    VARCHAR (100))
RETURNS INTEGER
AS
BEGIN
    DECLARE @extentTotal    INT;
    DECLARE @colon          INT;
     
    DECLARE @firstExtent    INT;
    DECLARE @secondExtent   INT;
 
    SET @extentTotal = 0;
    SET @colon = CHARINDEX (':', @extents);
 
    -- Check for the single extent case
    --
    IF (CHARINDEX (':', @extents, @colon + 1) = 0)
        SET @extentTotal = 1;
    ELSE
        -- We're in the multi-extent case
        --
        BEGIN
        SET @firstExtent = CONVERT (INT,
            SUBSTRING (@extents, @colon + 1, CHARINDEX (')', @extents, @colon) - @colon - 1));
        SET @colon = CHARINDEX (':', @extents, @colon + 1);
        SET @secondExtent = CONVERT (INT,
            SUBSTRING (@extents, @colon + 1, CHARINDEX (')', @extents, @colon) - @colon - 1));
        SET @extentTotal = (@secondExtent - @firstExtent) / 8 + 1;
    END
 
    RETURN @extentTotal;
END
GO




USE [msdb]
GO



SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 
-- This SP cracks all differential bitmap pages for all online
-- data files in a database. It creates a sum of changed extents
-- and reports it as follows (example small msdb):
-- 
-- EXEC sp_SQLskillsDIFForFULL 'msdb';
-- GO
--
-- Total Extents Changed Extents Percentage Changed
-- ------------- --------------- ----------------------
-- 102           56              54.9
--
-- Note that after a full backup you will always see some extents
-- marked as changed. The number will be 4 + (number of data files - 1).
-- These extents contain the file headers of each file plus the
-- roots of some of the critical system tables in file 1.
-- The number for msdb may be around 20.
--
CREATE PROCEDURE [dbo].[sp_DBADIFForFULL] (
    @dbName SYSNAME, @sizeTotal BIGINT OUTPUT, @DIFFTotal BIGINT OUTPUT)
AS
BEGIN
    SET NOCOUNT ON;
 
    -- Create the temp table
    --
    IF EXISTS (SELECT * FROM [msdb].[dbo].[sysobjects] WHERE NAME = N'DBADBCCPage')
        DROP TABLE [msdb].[dbo].[DBADBCCPage];
 
    CREATE TABLE msdb.dbo.DBADBCCPage (
        [ParentObject]  VARCHAR (100),
        [Object]        VARCHAR (100),
        [Field]         VARCHAR (100),
        [VALUE]         VARCHAR (100)); 
 
    DECLARE @fileID          INT;
    DECLARE @fileSizePages   INT;
    DECLARE @extentID        INT;
    DECLARE @pageID          INT;
    DECLARE @total           BIGINT;
    DECLARE @dbccPageString  VARCHAR (200);
 
    SELECT @DIFFtotal = 0;
    SELECT @sizeTotal = 0;
 
    -- Setup a cursor for all online data files in the database
    --

	SELECT 
		fileid AS file_id,
		size,
		dbid AS database_id
	INTO #masterfiles
	FROM sys.sysaltfiles
	WHERE groupid > 0

	EXEC sp_msforeachdb '
		USE [?]; 
		UPDATE MF 
		SET size = SF.size
		FROM #masterfiles AS MF 
		INNER JOIN sysfiles AS SF
			ON MF.file_id = SF.fileid
		WHERE MF.database_id = DB_ID()'



	
    DECLARE [files] CURSOR FOR

        SELECT [file_id], [size] FROM #masterfiles
        WHERE [database_id] = DB_ID (@dbName);

		
		
 
    OPEN files;
 
    FETCH NEXT FROM [files] INTO @fileID, @fileSizePages;
 
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @extentID = 0;
 
        -- The size returned from master.sys.master_files is in
        -- pages - we need to convert to extents
        --
        SELECT @sizeTotal = @sizeTotal + @fileSizePages / 8;
 
        WHILE (@extentID < @fileSizePages)
        BEGIN
            SELECT @pageID = @extentID + 6;
 
            -- Build the dynamic SQL
            --
            SELECT @dbccPageString = 'DBCC PAGE (['
                + @dbName + '], '
                + CAST (@fileID AS VARCHAR) + ', '
                + CAST (@pageID AS VARCHAR) + ', 3) WITH TABLERESULTS, NO_INFOMSGS';
 
            -- Empty out the temp table and insert into it again
            --
            TRUNCATE TABLE [msdb].[dbo].[DBADBCCPage];
            INSERT INTO [msdb].[dbo].[DBADBCCPage] EXEC (@dbccPageString);
 
            -- Aggregate all the changed extents using the function
            --
            SELECT @total = SUM ([msdb].[dbo].[DBAConvertToExtents] ([Field]))
            FROM [msdb].[dbo].[DBADBCCPage]
            WHERE [VALUE] = '    CHANGED'
            AND [ParentObject] LIKE 'DIFF_MAP%';
 
            SET @DIFFtotal = @DIFFtotal + @total;
 
            -- Move to the next GAM extent
            SET @extentID = @extentID + 511232;
        END
 
        FETCH NEXT FROM [files] INTO @fileID, @fileSizePages;
    END;
 
    -- Clean up
    --
    DROP TABLE [msdb].[dbo].[DBADBCCPage];
    CLOSE [files];
    DEALLOCATE [files];
 
    -- Output the results]
    --
    --SELECT
    --    @sizeTotal AS [Total Extents],
    --    @DIFFtotal AS [Changed Extents],
    --    ROUND (
    --        (CONVERT (FLOAT, @DIFFtotal) /
    --        CONVERT (FLOAT, @sizeTotal)) * 100, 2) AS [Percentage Changed];
END;
GO




USE msdb
CREATE TABLE [dbo].[database_changed_data] (
	 [Database Name] nvarchar(128) NOT NULL
	,[Total Extents] int NULL
	,[Changed Extents] int null
	,[Percentage Changed] numeric(7,2) null
	,[Time] datetime null
	,[Total Size (MB)] numeric(17,6) null
	,[Changed Size (MB)] numeric(17,6) null
)

GO



USE [msdb]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[get_database_changed_data] AS
BEGIN
IF OBJECT_ID('tempdb..#data') iS NOT NULL
	DROP TABLE #data

CREATE TABLE #data (
	[Database Name] sysname,
	[Total Extents] int,
	[Changed Extents] int,
	[Percentage Changed] numeric(7,2),
	[Time] datetime
)

SET NOCOUNT ON;

DECLARE @name sysname
DECLARE @size BIGINT, @diff BIGINT

DECLARE c CURSOR STATIC LOCAL FORWARD_ONLY READ_ONLY 
FOR
SELECT name
FROM master.dbo.sysdatabases
WHERE dbid >  4

OPEN c
FETCH NEXT FROM c INTO @name

WHILE @@FETCH_STATUS = 0
BEGIN 

	EXEC [msdb].[dbo].[sp_DBADIFForFULL] @name, @size OUTPUT, @diff OUTPUT;

	INSERT INTO #data (
		[Database Name],
		[Total Extents],
		[Changed Extents],
		[Percentage Changed],
		[Time]
	) 
	VALUES (
		@name,
		@size,
		@diff,
		ROUND (
            (CONVERT (FLOAT, @diff) /
            CONVERT (FLOAT, @size)) * 100, 2),
		GETDATE()
	)

	FETCH NEXT FROM c INTO @name
END

CLOSE c 
DEALLOCATE c

INSERT INTO msdb.dbo.database_changed_data ([Database Name],[Total Extents],[Changed Extents],[Percentage Changed],[Time],[Total Size (MB)],[Changed Size (MB)])
SELECT 
	*
	,[Total Extents]*8*8/1024.0 as [Total Size (MB)]
	,[Changed Extents]*8*8/1024.0 as [Changed Size (MB)]
FROM #data

END

GO


USE [msdb]
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'get_database_changed_data', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [exec proc]    Script Date: 09/01/2020 14:37:30 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'exec proc', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXECUTE msdb.dbo.get_database_changed_data', 
		@database_name=N'msdb', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'every hour', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20191217, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
