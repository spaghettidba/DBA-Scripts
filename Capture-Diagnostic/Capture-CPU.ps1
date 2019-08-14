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


$param = @{
    SqlInstance     = $DestinationServer
    Database        = $DestinationDatabase
    Schema          = $DestinationSchema
    AutoCreateTable = $true
    Table           = "CpuUtilization"
}

Get-DbaCpuRingBuffer -SqlInstance $SourceServer | 
    Where-Object {$_ -ne $null } | 
    Select-Object SqlInstance, EventTime, SQLProcessUtilization, OtherProcessUtilization |
    Write-DbaDataTable @param 
