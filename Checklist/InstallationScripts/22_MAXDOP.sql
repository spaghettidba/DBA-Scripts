EXEC sp_configure 'advanced', 1;
RECONFIGURE WITH OVERRIDE;
GO
EXEC sp_configure 'cost threshold for parallelism', 50;
EXEC sp_configure 'max degree of parallelism', 2;
RECONFIGURE WITH OVERRIDE;
GO

