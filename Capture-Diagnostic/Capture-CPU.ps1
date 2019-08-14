
$param = @{
    SqlInstance     = "localhost\sqlexpress2016"
    Database        = "testdiagnostic"
    Schema          = "dbo"
    AutoCreateTable = $true
    Table           = "CpuUtilization"
}

Get-DbaCpuRingBuffer -SqlInstance "localhost\sqlexpress2016" | 
    Where-Object {$_ -ne $null } | 
    Select-Object SqlInstance, EventTime, SQLProcessUtilization, OtherProcessUtilization |
    Write-DbaDataTable @param 
