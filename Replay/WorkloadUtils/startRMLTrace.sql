
IF OBJECT_ID('tempdb..#tmpPPEventEnable') IS NOT NULL DROP PROCEDURE #tmpPPEventEnable
GO
create procedure #tmpPPEventEnable @TraceID int, @iEventID int
as
begin
    set nocount on
    declare @iColID int
    declare @iColIDMax int
    declare @on bit
    set @on= 1
    set @iColID = 1
    set @iColIDMax = 64
    while(@iColID <= @iColIDMax)
    begin
        exec sp_trace_setevent @TraceID, @iEventID, @iColID, @on
        set @iColID = @iColID + 1
    end
end
go
-- Create a Queue
declare @rc int
declare @TraceID int
declare @maxfilesize bigint
set @maxfilesize = 250-- An optimal size for tracing and handling the files
-- Please replace the text InsertFileNameHere, with an appropriate
-- file name prefixed by a path, e.g., c:\MyFolder\MyTrace. The .trc extension
-- will be appended to the filename automatically.
exec @rc = sp_trace_create @TraceID output, 2 /* rollover*/, N'$(TraceFileName)', @maxfilesize, NULL
if (@rc != 0) goto error
declare @off bit
set @off = 0
-- Set the events
exec #tmpPPEventEnable @TraceID, 10 -- RPC Completed
exec #tmpPPEventEnable @TraceID, 11 -- RPC Started
declare @strVersion varchar(10)
set @strVersion = cast(SERVERPROPERTY('ProductVersion') as varchar(10))
if( (select cast( substring(@strVersion, 0, charindex('.', @strVersion)) as int)) >= 9)
begin
    exec sp_trace_setevent @TraceID, 10, 1, @off -- No Text for RPC, only Binary for performance
    exec sp_trace_setevent @TraceID, 11, 1, @off -- No Text for RPC, only Binary for performance
end
exec #tmpPPEventEnable @TraceID, 44 -- SP:StmtStarting
exec #tmpPPEventEnable @TraceID, 45 -- SP:StmtCompleted
exec #tmpPPEventEnable @TraceID, 100 -- RPC Output Parameter
exec #tmpPPEventEnable @TraceID, 12 -- SQL Batch Completed
exec #tmpPPEventEnable @TraceID, 13 -- SQL Batch Starting
exec #tmpPPEventEnable @TraceID, 40 -- SQL:StmtStarting
exec #tmpPPEventEnable @TraceID, 41 -- SQL:StmtCompleted
exec #tmpPPEventEnable @TraceID, 17 -- Existing Connection
exec #tmpPPEventEnable @TraceID, 14 -- Audit Login
exec #tmpPPEventEnable @TraceID, 15 -- Audit Logout
exec #tmpPPEventEnable @TraceID, 16 -- Attention
exec #tmpPPEventEnable @TraceID, 19 -- DTC Transaction
exec #tmpPPEventEnable @TraceID, 50 -- SQL Transaction
exec #tmpPPEventEnable @TraceID, 50 -- SQL Transaction
exec #tmpPPEventEnable @TraceID, 181 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 182 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 183 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 184 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 185 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 186 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 187 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 188 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 191 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 192 -- Tran Man Event
exec #tmpPPEventEnable @TraceID, 98 -- Stats Profile
exec #tmpPPEventEnable @TraceID, 53 -- Cursor Open
exec #tmpPPEventEnable @TraceID, 70 -- Cursor Prepare
exec #tmpPPEventEnable @TraceID, 71 -- Prepare SQL
exec #tmpPPEventEnable @TraceID, 73 -- Unprepare SQL
exec #tmpPPEventEnable @TraceID, 74 -- Cursor Execute
exec #tmpPPEventEnable @TraceID, 76 -- Cursor Implicit Conversion
exec #tmpPPEventEnable @TraceID, 77 -- Cursor Unprepare
exec #tmpPPEventEnable @TraceID, 78 -- Cursor Close
exec #tmpPPEventEnable @TraceID, 22 -- Error Log
exec #tmpPPEventEnable @TraceID, 25 -- Deadlock
exec #tmpPPEventEnable @TraceID, 27 -- Lock Timeout
exec #tmpPPEventEnable @TraceID, 60 -- Lock Escalation
exec #tmpPPEventEnable @TraceID, 28 -- MAX DOP
exec #tmpPPEventEnable @TraceID, 33 -- Exceptions
exec #tmpPPEventEnable @TraceID, 34 -- Cache Miss
exec #tmpPPEventEnable @TraceID, 37 -- Recompile
exec #tmpPPEventEnable @TraceID, 39 -- Deprocated Events
exec #tmpPPEventEnable @TraceID, 55 -- Hash Warning
exec #tmpPPEventEnable @TraceID, 58 -- Auto Stats
exec #tmpPPEventEnable @TraceID, 67 -- Execution Warnings
exec #tmpPPEventEnable @TraceID, 69 -- Sort Warnings
exec #tmpPPEventEnable @TraceID, 79 -- Missing Col Stats
exec #tmpPPEventEnable @TraceID, 80 -- Missing Join Pred
exec #tmpPPEventEnable @TraceID, 81 -- Memory change event
exec #tmpPPEventEnable @TraceID, 92 -- Data File Auto Grow
exec #tmpPPEventEnable @TraceID, 93 -- Log File Auto Grow
exec #tmpPPEventEnable @TraceID, 116 -- DBCC Event
exec #tmpPPEventEnable @TraceID, 125 -- Deprocation Events
exec #tmpPPEventEnable @TraceID, 126 -- Deprocation Final
exec #tmpPPEventEnable @TraceID, 127 -- Spills
exec #tmpPPEventEnable @TraceID, 137 -- Blocked Process Threshold
exec #tmpPPEventEnable @TraceID, 150 -- Trace file closed
exec #tmpPPEventEnable @TraceID, 166 -- Statement Recompile
exec #tmpPPEventEnable @TraceID, 196 -- CLR Assembly Load
-- Filter out all sp_trace based commands to the replay does not start this trace
-- Text filters can be expensive so you may want to avoid the filtering and just
-- remote the sp_trace commands from the RML files once processed.

$(TraceFilters)

--exec sp_trace_setfilter @TraceID, 1, 0, 7, N'%sp_trace%'
-- Set the trace status to start
exec sp_trace_setstatus @TraceID, 1
/*
exec sp_trace_setstatus 2, 0
exec sp_trace_setstatus 2, 2
*/
print 'Issue the following command(s) when you are ready to stop the tracing activity'
print 'exec sp_trace_setstatus ' + cast(@TraceID as varchar) + ', 0'
print 'exec sp_trace_setstatus ' + cast(@TraceID as varchar) + ', 2'
goto finish
error:
select ErrorCode=@rc
finish:

select @traceId AS TraceId
go



