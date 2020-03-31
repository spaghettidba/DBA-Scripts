[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [String] $SqlInstance,
    [Parameter(Mandatory)]
    [String] $RootBackupFolder,
    [Parameter(Mandatory)]
    [ValidateSet('FULL','DIFF','LOG')]
    [String] $BackupType,
    [String] $OutcomeInstance,
    [String] $OutcomeDatabase,
    [String] $OutcomeTable,
    [int] $FileCount = 0
)



if($BackupType -eq "LOG"){
    $models = 'Full', 'BulkLogged'
}
else {
    $models = 'Full', 'BulkLogged', 'Simple'
}

$databases = Get-DbaDatabase -SqlInstance $SqlInstance -ExcludeDatabase "tempdb" -Status "Normal" -RecoveryModel $models
$Basefolder = Join-Path -Path $RootBackupFolder -ChildPath $SqlInstance
if(-not (Test-Path $Basefolder )) {
    New-Item $Basefolder -ItemType Directory | Out-Null
}
foreach($database in $databases){
    $outputfolder = Join-Path -Path $Basefolder -ChildPath "\$($Database.Name)\$BackupType"

    If(-not(Test-Path $outputfolder)){
        New-Item $outputfolder -ItemType Directory | Out-Null
    }
    $extension = "bak"
    if($BackupType -eq "LOG") { $extension = "trn" }
    if(($BackupType -eq "DIFF") -and ($database.Name -eq "master")) { continue } # no DIFF backups for master
    $backupOutcome = Backup-DbaDatabase -SqlInstance $SqlInstance -Database $($Database.Name) -BackupDirectory $outputfolder -Type $BackupType  -BackupFileName "servername_instancename_dbname_backuptype_timestamp.$extension" -ReplaceInName -CompressBackup -FileCount $FileCount
    if($OutcomeInstance) {
        $backupOutcome | Write-DbaDataTable -SqlInstance $OutcomeInstance -Database $OutcomeDatabase -Table $OutcomeTable -AutoCreateTable
    }
}

