
SELECT [Database Name]
      ,[Total Extents]
      ,[Changed Extents]
      ,[Percentage Changed]
      ,[Time]
      ,[Total Size (MB)]
      ,[Changed Size (MB)]
      ,[Changed Since] = bs.backup_start_date
  FROM [msdb].[dbo].[database_changed_data] AS cd
  LEFT JOIN msdb.dbo.backupset AS bs
        ON cd.[database name] = bs.database_name
        AND bs.type = 'D'
        AND bs.backup_start_date = (
            SELECT MAX(backup_start_date) 
            FROM msdb.dbo.backupset AS mbs
            WHERE database_name = cd.[database name]
                AND type = 'D'
                AND backup_start_date < cd.time
        )

