-------------------------------------------------------
-- STOP TRACE FOR ERROR TRAPPING DURING REPLAY       --
-------------------------------------------------------

SET NOCOUNT ON;

-- Create a Queue
DECLARE @TraceID int


SELECT @TraceID = id
FROM sys.traces
WHERE path LIKE N'$(TraceFileName)%.trc'

IF @TraceID IS NOT NULL 
BEGIN
	EXEC sp_trace_setstatus @TraceId, 0
	EXEC sp_trace_setstatus @TraceId, 2
END
