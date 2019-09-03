[CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=1)]
        [string[]]$TargetServer = "TSTSQL23",
        [Parameter(Mandatory=$true, Position=2)]
        [string]$ImagePath = '\\lanfges\sistemi\software\server\Application Server\SQL Server\2017\en_sql_server_2017_developer_x64_dvd_11296168.iso',
        [Parameter(Mandatory=$false, Position=3)]
        [string]$SqlCollation = "SQL_Latin1_General_CP1_CI_AS",
        [Parameter(Mandatory=$false, Position=4)]
        [string[]]$SysadminAccounts = "LANFGES\GG_R_GES - DBADMINS"
    )

$theMount = Get-DiskImage -ImagePath $imagePath
if(-not $theMount.Attached) {
    $theMount = Mount-DiskImage -ImagePath $ImagePath -PassThru 
}
$driveLetter = ($theMount | Get-Volume).DriveLetter

Set-Location $($driveLetter + ":\") 

$config = @{
    AGTSVCSTARTUPTYPE     = "Automatic"
    SQLCOLLATION          = $SqlCollation
    BROWSERSVCSTARTUPTYPE = "Disabled"
    FILESTREAMLEVEL       = 2
    FILESTREAMSHARENAME   = "MSSQL"
    INSTANCEDIR           = "C:\Program Files\Microsoft SQL Server"
    INSTALLSQLDATADIR     = "D:"
    TCPENABLED            = "1"
    SQLSYSADMINACCOUNTS   = $SysadminAccounts
}

$SqlCred = Get-Credential -Message "Credential for SQL Server service"
$AgtCred = Get-Credential -Message "Credential for SQL Server Agent service"



install-dbainstance `
    -Configuration $config `
    -Path $($driveLetter + ":\") `
    -SQLInstance $TargetServer `
    -Version "2017" `
    -Feature "Default" `
    -BackupPath "D:\MSSQL14.MSSQLSERVER\MSSQL\Backup" `
    -DataPath "D:\MSSQL14.MSSQLSERVER\MSSQL\DATA" `
    -LogPath "L:\MSSQL14.MSSQLSERVER\MSSQL\DATA" `
    -TempPath "D:\MSSQL14.MSSQLSERVER\MSSQL\DATA" `
    -EngineCredential $SqlCred `
    -AgentCredential $AgtCred `
    -PerformVolumeMaintenanceTasks `
    -EnableException `
    -Restart 
    


Set-DbaStartupParameter -SqlInstance $TargetServer -TraceFlag 3226

$updatePath = Split-Path -parent $ImagePath

Update-DbaInstance -ComputerName $TargetServer -Path $updatePath -Restart