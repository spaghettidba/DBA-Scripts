WITH disks AS (
    SELECT 
         SUBSTRING(volume_mount_point, 1, 1) AS volume_mount_point
        ,SUM(CASE WHEN f.type_desc = 'LOG' THEN 0 ELSE 1 END) AS data_files
        ,SUM(CASE WHEN f.type_desc = 'LOG' THEN 1 ELSE 0 END) AS log_files
        ,SUM(CASE WHEN f.database_id = 2 THEN 1 ELSE 0 END) AS tempdb_files
        ,MIN(total_bytes/1024/1024) AS total_MB
        ,MIN(available_bytes/1024/1024) AS available_MB
    FROM
        sys.master_files AS f
    CROSS APPLY
        sys.dm_os_volume_stats(f.database_id, f.file_id)
    GROUP BY SUBSTRING(volume_mount_point, 1, 1)
)
SELECT 
     volume_mount_point
    ,disk_type = 
        CASE 
            WHEN data_files = MAX(data_files) OVER() THEN 'DATA'
            WHEN log_files = MAX(log_files) OVER() THEN 'LOG'
            WHEN tempdb_files = MAX(tempdb_files) OVER() THEN 'TEMPDB'
        END
    ,total_MB
    ,available_MB
FROM disks
ORDER BY 1