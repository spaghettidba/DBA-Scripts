EXEC sp_configure 'min server memory (MB)', 0;

-- run only if not managed by setup
-- EXEC sp_configure 'max server memory (MB)', 55000;
RECONFIGURE;
GO

EXEC sp_configure 'advanced',1;
RECONFIGURE;

EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE;