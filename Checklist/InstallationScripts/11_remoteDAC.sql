EXEC sp_configure 'advanced', 1;
RECONFIGURE;
GO

EXEC sp_configure 'remote admin connections', 1;
RECONFIGURE;
GO

