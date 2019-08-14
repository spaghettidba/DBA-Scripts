
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
        $ServerName = $_.SqlInstance

        $snapshotProp = @{
            Label = "snapshot_id"
            Expression = {$SnapshotId}
        }
        $serverProp = @{
            Label = "Server Name"
            Expression = {$ServerName}
        }
        $databaseProp = @{
            Label = "Database Name"
            Expression = {$DatabaseName}
        }

        $expr = '$_.Result | Select-Object $snapshotProp, '

        # Decide whether collection needs an additional "server" column
        # Two different checks are required, because the input collection
        # could contain objects of different types (System.Data.DataRow or PsCustomObject)
        if(-not (($_.Result.PSObject.Properties | Select-Object -Expand Name) -contains "Server Name")) {
            if(($_.Result | Get-Member -MemberType NoteProperty -Name "Server Name" | Measure-Object).Count -eq 0) {
                $expr += ' $serverProp, '
            }
        }

        # Decide whether collection needs an additional "database" column
        # again, two different checks
        if($_.DatabaseSpecific) {
            if(-not (($_.Result.PSObject.Properties | Select-Object -Expand Name) -contains "Database Name")) {
                if(($_.Result | Get-Member -MemberType NoteProperty -Name "Database Name" | Measure-Object).Count -eq 0) {
                    $expr += ' $databaseProp, '
                }
            }
        }

        $expr += '*'

        $param = @{
            SqlInstance     = "localhost\sqlexpress2016"
            Database        = "testdiagnostic"
            Schema          = "dbo"
            AutoCreateTable = $true
            Table           = $TableName
            InputObject     = Invoke-Expression $expr
        }
        Write-DbaDataTable @param 
    }