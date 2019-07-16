EXEC sp_configure 'min server memory (MB)', 0;
EXEC sp_configure 'max server memory (MB)', 55000;
RECONFIGURE WITH OVERRIDE;
GO

