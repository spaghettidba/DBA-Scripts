[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [String] $RootBackupFolder,
    [Parameter(Mandatory)]
    [ValidateSet('FULL','DIFF','LOG')]
    [String] $BackupType,
    [String] $OutcomeInstance,
    [String] $OutcomeDatabase,
    [String] $OutcomeTable,
    [int] $FileCount = 0,
    [String] $IncludeServerName,
    [String] $ExcludeServerName
)

# Create an empty array to store jobs
$jobs = @()

$Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(500,25)

$sb = {
    param([string]$FilePath, [string]$SqlInstance, [string]$RootBackupFolder, [string]$BackupType, [String] $OutcomeInstance, [String] $OutcomeDatabase, [String] $OutcomeTable, [int] $FileCount)
    [Powershell]::Create().AddCommand($FilePath).AddParameters(@{SqlInstance = $SqlInstance; RootBackupFolder = $RootBackupFolder; BackupType = $BackupType; OutcomeInstance = $OutcomeInstance; OutcomeDatabase = $OutcomeDatabase; OutcomeTable = $OutcomeTable; FileCount = $FileCount}).Invoke()
}

Get-Content "$PSScriptRoot\servers.txt" | 
    Where-Object { ((-not $IncludeServerName) -or ($PSItem -eq $IncludeServerName)) -and ($PSItem -ne $ExcludeServerName) } |
    ForEach-Object {
        if($BackupType -eq "LOG"){
            # Log backups should be run at the same time on all servers
            # Start a job asynchronously
            # If a previous log backup is running, this command will have to wait
            $jobs += Start-Job -ScriptBlock $sb -ArgumentList @("$PSScriptRoot\backup-allDatabases.ps1", $PSItem, $RootBackupFolder, $BackupType, $OutcomeInstance, $OutcomeDatabase, $OutcomeTable, $FileCount) -Name $PSItem
        }
        else {
            Invoke-Command -ScriptBlock $sb -ArgumentList @("$PSScriptRoot\backup-allDatabases.ps1", $PSItem, $RootBackupFolder, $BackupType, $OutcomeInstance, $OutcomeDatabase, $OutcomeTable, $FileCount) *> $PSScriptRoot\LOGS\$($PSItem.Replace("\","_"))_$($BackupType)_$(Get-Date -Format yyyyMMdd-hhmmss).log
        }
    }

$jobs | ForEach-Object {
        $JobName = $PSItem.Name
        Receive-Job -Job $PSItem -Wait -WriteEvents -AutoRemoveJob > $PSScriptRoot\LOGS\$($JobName.Replace("\","_"))_$($BackupType)_$(Get-Date -Format yyyyMMdd-hhmmss).log
    }