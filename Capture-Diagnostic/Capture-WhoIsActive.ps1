$installResults = Install-DbaWhoIsActive -SqlInstance "localhost\sqlexpress2016" -Database master


[int]$snapshotId = (Get-Date -Format "yyyyMMdd")

$snapshotProp = @{
    Label = "snapshot_id"
    Expression = {$SnapshotId}
}
$serverProp = @{
    Label = "Server Name"
    Expression = {$installResults.SqlInstance}
}

$param = @{
    SqlInstance     = "localhost\sqlexpress2016"
    Database        = "testdiagnostic"
    Schema          = "dbo"
    AutoCreateTable = $true
    Table           = "WhoIsActive"
}

Invoke-DbaWhoIsActive -SqlInstance "localhost\sqlexpress2016" -FindBlockLeaders -GetOuterCommand -GetPlans 1 |
    Where-Object {$_ -ne $null } | 
    Select-Object $snapshotProp, $serverProp, * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors |
    Write-DbaDataTable @param 
