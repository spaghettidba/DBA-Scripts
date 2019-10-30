[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [String] $RootBackupFolder,
    [Parameter(Mandatory)]
    [int] $RetentionDays
)
Get-ChildItem -Path $RootBackupFolder -Recurse -File | Where-Object {$PSItem.CreationTime -lt (get-date).AddDays($RetentionDays) } | Remove-Item