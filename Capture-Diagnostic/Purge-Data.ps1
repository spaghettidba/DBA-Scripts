[CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=1)]
        [string]$DestinationServer,
        [Parameter(Mandatory=$false, Position=2)]
        [string]$DestinationDatabase = "diagnostic",
        [Parameter(Mandatory=$false, Position=3)]
        [string]$DestinationSchema = "dbo",
        [Parameter(Mandatory=$false, Position=4)]
        [int]$RetentionDays = 30
    )

$sql = "
    SELECT OBJECT_NAME(object_id) AS Table_Name
    FROM sys.columns
    WHERE name = 'snapshot_id'
        AND OBJECT_SCHEMA_NAME(object_id) = '$DestinationSchema'
        AND TYPE_NAME(system_type_id) = 'int'
"

[int]$snapshot_id = (get-date (get-date).AddDays(-$RetentionDays) -Format "yyyyMMdd")

Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql -EnableException |
    ForEach-Object {
        $sql = "DELETE FROM [$DestinationSchema].[$($_.Table_Name)] WHERE snapshot_id < $snapshot_id "         
        Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql -EnableException
    }



$sql = "
    SELECT OBJECT_NAME(object_id) AS Table_Name
    FROM sys.columns
    WHERE name = 'snapshot_id'
        AND OBJECT_SCHEMA_NAME(object_id) = '$DestinationSchema'
        AND TYPE_NAME(system_type_id) = 'bigint'
"

[int]$snapshot_id = (get-date (get-date).AddDays(-$RetentionDays) -Format "yyyyMMddHHmmss")

Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql -EnableException |
    ForEach-Object {
        $sql = "DELETE FROM [$DestinationSchema].[$($_.Table_Name)] WHERE snapshot_id < $snapshot_id "         
        Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql -EnableException
    }

$event_time = (get-date).AddDays(-$RetentionDays)

$sql = "DELETE FROM [$DestinationSchema].[CpuUtilization] WHERE EventTime < $event_time "  
    Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql -EnableException