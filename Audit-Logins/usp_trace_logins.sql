USE [master]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('usp_trace_logins') IS NOT NULL
    DROP PROCEDURE usp_trace_logins;

EXEC('CREATE PROCEDURE [dbo].[usp_trace_logins] AS BEGIN RETURN 0 END')
GO

ALTER PROCEDURE [dbo].[usp_trace_logins]
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @ret int;
    SET @ret = 0;

    -- CHECK SERVER VERSION:
    -------------------------------------------------------------------
    -- SQL 2000 DOES NOT ALLOW @filecount AS A PARAM TO sp_trace_create
    -- SQL 2000 DOES NOT ALLOW READING FROM A TRACE WITHOUT STOPPING IT
    DECLARE @version nvarchar(100)
    SET @version = CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(100));


    IF EXISTS(
        SELECT * 
        FROM :: fn_trace_getinfo(default)
        WHERE CAST(value AS nvarchar(500)) LIKE '%logins%'
    )
    BEGIN
        DECLARE @path nvarchar(128)
        DECLARE @id int

        SELECT 
            @id = traceid,
            @path = CAST(value AS nvarchar(128)) 
        FROM :: fn_trace_getinfo(default)
        WHERE CAST(value AS nvarchar(500)) LIKE '%logins%'


        IF LEFT(@version, CHARINDEX('.',@version,1) - 1) = '8'
        BEGIN
            SET @path = @path + '.trc'

            -- if the trace is running, stop it
            exec sp_trace_setstatus @id, 0
            exec sp_trace_setstatus @id, 2
        END



        IF OBJECT_ID('watchlogins') IS NULL
        BEGIN 

            PRINT 'Creating table watchlogins...'

            SELECT TOP 0
                ISNULL(LoginName,'') AS LoginName, 
                ISNULL(DatabaseName,'') AS DatabaseName, 
                ISNULL(HostName,'') AS HostName, 
                ISNULL(ApplicationName,'') AS ApplicationName,  
                CAST(0 AS bigint) AS num, 
                GETDATE() AS MinTime, 
                GETDATE() AS MaxTime
            INTO watchlogins
            FROM ::fn_trace_gettable(@path,DEFAULT);

            CREATE UNIQUE CLUSTERED INDEX CI_watchlogins ON watchlogins(Maxtime, LoginName, DatabaseName, Hostname, ApplicationName)
        END

        PRINT 'Merging data into watchlogins...'

        DECLARE @MaxTime datetime;
        SELECT @MaxTime = MAX(MaxTime) FROM watchlogins;
        IF @MaxTime IS NULL
            SET @MaxTime = DATEADD(year, -1, GETDATE());

        UPDATE wl
        SET num = wl.num + trc.num,
            MinTime = CASE WHEN trc.MinTime < wl.MinTime THEN trc.MinTime ELSE wl.MinTime END,
            MaxTime = CASE WHEN trc.MaxTime > wl.MaxTime THEN trc.MaxTime ELSE wl.MaxTime END
        FROM watchlogins AS wl
        INNER JOIN (
            SELECT LoginName, DatabaseName, HostName, ApplicationName, COUNT(*) AS num, MIN(StartTime) AS MinTime, MAX(StartTime) AS MaxTime
            FROM ::fn_trace_gettable(@path,DEFAULT)
            WHERE StartTime > @MaxTime
            GROUP BY LoginName, DatabaseName, HostName, ApplicationName
        ) AS trc
            ON  ISNULL(trc.LoginName,'')       = wl.LoginName
            AND ISNULL(trc.DatabaseName,'')    = wl.DatabaseName
            AND ISNULL(trc.HostName,'')        = wl.HostName
            AND ISNULL(trc.ApplicationName,'') = wl.ApplicationName


        INSERT INTO watchlogins
        SELECT 
            ISNULL(LoginName,'') AS LoginName, 
            ISNULL(DatabaseName,'') AS DatabaseName, 
            ISNULL(HostName,'') AS HostName, 
            ISNULL(ApplicationName,'') AS ApplicationName, 
            COUNT(*) AS num, 
            MIN(StartTime) AS MinTime, 
            MAX(StartTime) AS MaxTime
        FROM ::fn_trace_gettable(@path,DEFAULT) AS trc
        WHERE StartTime > @MaxTime
        GROUP BY LoginName, DatabaseName, HostName, ApplicationName
        HAVING NOT EXISTS (
            SELECT *
            FROM watchlogins AS wl
            WHERE   ISNULL(trc.LoginName,'')       = wl.LoginName
                AND ISNULL(trc.DatabaseName,'')    = wl.DatabaseName
                AND ISNULL(trc.HostName,'')        = wl.HostName
                AND ISNULL(trc.ApplicationName,'') = wl.ApplicationName
            )



    END
    

    IF NOT EXISTS(
        SELECT * 
        FROM :: fn_trace_getinfo(default)
        WHERE CAST(value AS nvarchar(500)) LIKE '%logins%'
    )
    BEGIN

        declare @TraceID int
        declare @maxfilesize bigint
        set @maxfilesize = 100

        -- obtain path to master log
        DECLARE @masterpath nvarchar(520)

        SELECT @masterpath = filename
        FROM sysaltfiles
        WHERE dbid = 1
            AND groupid = 1;

        SELECT @masterpath = SUBSTRING(@masterpath, 1, LEN(REVERSE(@masterpath)) - CHARINDEX('\',REVERSE(@masterpath))) 
        DECLARE @tracepath nvarchar(128)
        SET @tracepath = @masterpath + '\logins';


        IF LEFT(@version, CHARINDEX('.',@version,1) - 1) = '8'
        BEGIN
            
            -- done reading? delete the trace file
            DECLARE @cmd nvarchar(4000)
            SET @cmd = N'DEL "' + @tracepath + '.trc"'
            CREATE TABLE #t ([output] nvarchar(4000))
            INSERT #t
            EXEC xp_cmdshell @cmd
            DROP TABLE #t


            PRINT 'Starting the logins trace'

            exec @ret = sp_trace_create
                @traceid = @TraceID output, 
                @options = 2, 
                @tracefile = @tracepath, 
                @maxfilesize = @maxfilesize, 
                @stoptime = NULL;

            IF @ret <> 0 
                PRINT 'Unable to start the trace: ' + CAST(@ret AS varchar(10))
        END
        ELSE
        BEGIN 

            PRINT 'Starting the logins trace'

            exec @ret = sp_trace_create
                @traceid = @TraceID output, 
                @options = 2, 
                @tracefile = @tracepath, 
                @maxfilesize = @maxfilesize, 
                @stoptime = NULL, 
                @filecount = 5;

            IF @ret <> 0 
                PRINT 'Unable to start the trace: ' + CAST(@ret AS varchar(10))
        END

        -- Set the events
        declare @on bit
        set @on = 1
        exec sp_trace_setevent @TraceID, 14, 10, @on
        exec sp_trace_setevent @TraceID, 14, 11, @on
        exec sp_trace_setevent @TraceID, 14, 8, @on
        exec sp_trace_setevent @TraceID, 14, 12, @on
        exec sp_trace_setevent @TraceID, 14, 14, @on
        exec sp_trace_setevent @TraceID, 14, 35, @on

        -- start the trace
        exec sp_trace_setstatus @TraceID, 1

    END

    PRINT 'Done.'

END
