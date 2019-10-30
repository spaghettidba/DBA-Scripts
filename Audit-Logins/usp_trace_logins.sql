USE [master]
GO

/****** Object:  StoredProcedure [dbo].[usp_trace_logins]    Script Date: 28/10/19 10:40:38 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_trace_logins]
AS
BEGIN

    SET NOCOUNT ON;

    IF NOT EXISTS(
        SELECT *
        FROM sys.traces
        WHERE path LIKE '%logins%.trc'
    )
    BEGIN


        declare @TraceID int
        declare @maxfilesize bigint
        set @maxfilesize = 50

        -- obtain path to master log
        DECLARE @masterpath nvarchar(255)

        SELECT @masterpath = physical_name
        FROM sys.master_files
        WHERE database_id = 1
            AND type = 1;

        SELECT @masterpath = SUBSTRING(@masterpath, 1, LEN(@masterpath) - CHARINDEX('\',REVERSE(@masterpath))) 
        DECLARE @tracepath nvarchar(255)
        SET @tracepath = @masterpath + '\logins';


        exec sp_trace_create @TraceID output, 2, @tracepath, @maxfilesize, NULL, 5

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


    DECLARE @path nvarchar(255)

    SELECT @path = path
    FROM sys.traces
    WHERE path LIKE '%logins%.trc'


    IF OBJECT_ID('watchlogins') IS NULL
    BEGIN 
        SELECT TOP(0) LoginName, DatabaseName, HostName, ApplicationName, 0 AS num, GETDATE() AS MinTime, GETDATE() AS MaxTime
        INTO watchlogins
        FROM fn_trace_gettable(@path,DEFAULT);

        CREATE CLUSTERED INDEX CI_watchlogins ON watchlogins(Maxtime, LoginName, DatabaseName, Hostname, ApplicationName)
    END

    DECLARE @MaxTime datetime;
    SELECT @MaxTime = MAX(MinTime) FROM watchlogins;
    IF @MaxTime IS NULL
        SET @MaxTime = DATEADD(year, -1, GETDATE());


    INSERT INTO watchlogins
    SELECT LoginName, DatabaseName, HostName, ApplicationName, COUNT(*) AS num, MIN(StartTime) AS MinTime, MAX(StartTime) AS MaxTime
    FROM fn_trace_gettable(@path,DEFAULT)
    WHERE StartTime > @MaxTime
    GROUP BY LoginName, DatabaseName, HostName, ApplicationName


END
GO


