SET NOCOUNT ON;

-- create a temporary table to hold data from sys.master_files
IF OBJECT_ID('tempdb..#masterfiles') IS NOT NULL
    DROP TABLE #masterfiles;
 
CREATE TABLE #masterfiles (
    database_id int,
    type_desc varchar(10),
    name sysname,
    physical_name varchar(255),
    size_mb int,
    max_size_mb int,
    growth int,
    is_percent_growth bit,
    data_space_id int,
    data_space_name nvarchar(128) NULL,
    drive nvarchar(512),
    mbfree int
);
 
-- extract file information from sys.master_files
-- and correlate each file to its logical volume
INSERT INTO #masterfiles
SELECT
     mf.database_id
    ,type_desc
    ,name
    ,physical_name
    ,size_mb = size / 128
    ,max_size_mb =
        CASE
            WHEN max_size = 268435456 AND type_desc = 'LOG' THEN -1
            ELSE
                CASE
                    WHEN max_size = -1 THEN -1
                    ELSE max_size / 128
                END
        END
    ,mf.growth
    ,mf.is_percent_growth
    ,mf.data_space_id
    ,NULL
    ,d.volume_mount_point
    ,d.available_bytes / 1024 / 1024
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(database_id, file_id) AS d;
 
-- add an "emptyspace" column to hold empty space for each file
ALTER TABLE #masterfiles ADD emptyspace_mb int NULL;
 
-- iterate through all databases to calculate empty space for its files
DECLARE @name sysname;
 
DECLARE c CURSOR FORWARD_ONLY READ_ONLY STATIC LOCAL
FOR
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
 
OPEN c
FETCH NEXT FROM c INTO @name
 
WHILE @@FETCH_STATUS = 0
BEGIN
 
    DECLARE @sql nvarchar(max)
    DECLARE @statement nvarchar(max)
    SET @sql = '
        UPDATE mf
        SET emptyspace_mb = size_mb - FILEPROPERTY(name,''SpaceUsed'') / 128,
            data_space_name =
                ISNULL(
                    (SELECT name FROM sys.data_spaces WHERE data_space_id = mf.data_space_id),
                    ''LOG''
                )
        FROM #masterfiles AS mf
        WHERE database_id = DB_ID();
    '
    SET @statement = 'EXEC ' + QUOTENAME(@name) + '.sys.sp_executesql @sql'
    EXEC sp_executesql @statement, N'@sql nvarchar(max)', @sql
 
    FETCH NEXT FROM c INTO @name
END
 
CLOSE c
DEALLOCATE c
 
-- create a scalar function to simulate the growth of the database in the drive's available space
IF OBJECT_ID('tempdb..calculateAvailableSpace') IS NOT NULL
    EXEC tempdb.sys.sp_executesql N'DROP FUNCTION calculateAvailableSpace'
 
EXEC tempdb.sys.sp_executesql N'
CREATE FUNCTION calculateAvailableSpace(
    @diskFreeSpaceMB float,
    @currentSizeMB float,
    @growth float,
    @is_percent_growth bit
)
RETURNS int
AS
BEGIN
    IF @currentSizeMB = 0
        SET @currentSizeMB = 1
    DECLARE @returnValue int = 0
    IF @is_percent_growth = 0
    BEGIN
        SET @returnValue = (@growth /128) * CAST((@diskFreeSpaceMB / (ISNULL(NULLIF(@growth,0),1) / 128)) AS int)
    END
    ELSE
    BEGIN
        DECLARE @prevsize AS float = 0
        DECLARE @calcsize AS float = @currentSizeMB
        WHILE @calcsize < @diskFreeSpaceMB
        BEGIN
            SET @prevsize = @calcsize
            SET @calcsize = @calcsize + @calcsize * @growth / 100.0
        END
        SET @returnValue = @prevsize - @currentSizeMB
        IF @returnValue < 0
            SET @returnValue = 0
    END
 
    RETURN @returnValue
END
'
 
-- report database filegroups with less than 20% available space
;WITH masterfiles AS (
    SELECT *
        ,available_space =
            CASE mf.max_size_mb
                WHEN -1 THEN tempdb.dbo.calculateAvailableSpace(mbfree, size_mb, growth, is_percent_growth)
                ELSE max_size_mb - size_mb
            END
            + emptyspace_mb
    FROM #masterfiles AS mf
),
spaces AS (
    SELECT
         DB_NAME(database_id) AS database_name
        ,data_space_name
        ,type_desc
        ,SUM(size_mb) AS size_mb
        ,SUM(available_space) AS available_space_mb
        ,SUM(available_space) * 100 /
            CASE SUM(size_mb)
                WHEN 0 THEN 1
                ELSE SUM(size_mb)
            END AS available_space_percent
    FROM masterfiles
    GROUP BY DB_NAME(database_id)
        ,data_space_name
        ,type_desc
)
SELECT *
FROM spaces
WHERE available_space_percent < 20
ORDER BY available_space_percent ASC
 
IF OBJECT_ID('tempdb..#masterfiles') IS NOT NULL
    DROP TABLE #masterfiles;
 
IF OBJECT_ID('tempdb..calculateAvailableSpace') IS NOT NULL
    EXEC tempdb.sys.sp_executesql N'DROP FUNCTION calculateAvailableSpace'