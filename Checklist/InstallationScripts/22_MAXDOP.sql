EXEC sp_configure 'advanced', 1;
RECONFIGURE;
GO
EXEC sp_configure 'cost threshold for parallelism', 50;

-- run only if not managed by setup
-- EXEC sp_configure 'max degree of parallelism', 2;
RECONFIGURE;
GO

