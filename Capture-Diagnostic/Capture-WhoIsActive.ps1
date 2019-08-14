[CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=1)]
        [string]$SourceServer,
        [Parameter(Mandatory=$true, Position=2)]
        [string]$DestinationServer,
        [Parameter(Mandatory=$false, Position=3)]
        [string]$DestinationDatabase = "diagnostic",
        [Parameter(Mandatory=$false, Position=4)]
        [string]$DestinationSchema = "dbo"
    )

    $CalculatedServerName = $SourceServer
    try {
        $installResults = Install-DbaWhoIsActive -SqlInstance $SourceServer -Database master
        $CalculatedServerName = $installResults.SqlInstance
    }
    catch {}


[int64]$snapshotId = (Get-Date -Format "yyyyMMddHHmmss")

$snapshotProp = @{
    Label = "snapshot_id"
    Expression = {$SnapshotId}
}
$serverProp = @{
    Label = "Server Name"
    Expression = {$CalculatedServerName}
}

$param = @{
    SqlInstance     = $DestinationServer
    Database        = $DestinationDatabase
    Schema          = $DestinationSchema
    AutoCreateTable = $true
    Table           = "WhoIsActive"
}

Invoke-DbaWhoIsActive -SqlInstance $SourceServer -FindBlockLeaders -GetOuterCommand -GetPlans 1 -ShowOwnSpid |
    Where-Object {$_ -ne $null } | 
    Select-Object $snapshotProp, $serverProp, * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors |
    Write-DbaDataTable @param 
