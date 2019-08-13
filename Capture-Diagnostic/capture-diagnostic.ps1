
$queries = @(
    "Top Waits",
    "Top Worker Time Queries",
    "PLE by NUMA Node",
    "Ad hoc Queries",
    "Top Logical Reads Queries",
    "Top Avg Elapsed Time Queries",
    "Top IO Statements",
    "Table Sizes",
    "Overall Index Usage - Reads",
    "Overall Index Usage - Writes",
    "Drive Level Latency",
    "Connection Counts by IP Address"
    "File Sizes and Space",
    "Log Space Usage",
    "IO Stats By File",
    "SP Execution Counts",
    "SP Avg Elapsed Time",
    "SP Worker Time",
    "SP Logical Reads",
    "SP Physical Reads",
    "SP Logical Writes"
)

[int]$snapshotId = (Get-Date -Format "yyyyMMdd")

Invoke-DbaDiagnosticQuery -SqlInstance "localhost\sqlexpress2016"  -QueryName $queries | 
    Where-Object { $_.Result -ne $null } | 
    ForEach-Object {
        $TableName = $_.Name
        $DatabaseName = $_.Database

        $snapshotProp = @{
            Label = "snapshot_id"
            Expression = {$SnapshotId}
        }

        $expr = '$_.Result | Select-Object $snapshotProp, *'

        # Decide whether $Data needs an additional "database" column

        if($_.DatabaseSpecific) {
            $databaseProp = @{
                Label = "Database Name"
                Expression = {$DatabaseName}
            }
            if((Get-Member -InputObject $_.Result -MemberType NoteProperty | Where-Object { $_.Name -eq "Database Name" } | Measure-Object) -eq 0) {
                $expr = '$_.Result | Select-Object $snapshotProp, $databaseProp, *'
            }
        }

        $param = @{
            SqlInstance     = "localhost\sqlexpress2016"
            Database        = "testdiagnostic"
            Schema          = "staging"
            AutoCreateTable = $true
            Table           = $TableName
            InputObject     = Invoke-Expression $expr
        }
        Write-DbaDataTable @param 
    }