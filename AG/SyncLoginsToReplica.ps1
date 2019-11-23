param (
    # define the AG name
    [Parameter(Mandatory=$true)][string]$AvailabilityGroupName,
    [Parameter(Mandatory=$true)][string]$AvailabilityGroupListener,
    [string]$ClientName = ‘AG Login Sync helper’
)
# internal variables
#$ClientName = ‘AG Login Sync helper’
$primaryInstance = $null
$secondaryInstances = @{}

try {
    # connect to the AG listener, get the name of the primary and all secondaries
    $replicas = Get-DbaAgReplica -SqlInstance $AvailabilityGroupListener -AvailabilityGroup $AvailabilityGroupName
    $primaryInstance = $replicas | Where Role -eq Primary | select -ExpandProperty name
    $secondaryInstances = $replicas | Where Role -ne Primary | select -ExpandProperty name
    # create a connection object to the primary
    $primaryInstanceConnection = Connect-DbaInstance $primaryInstance -ClientName $ClientName
    # loop through each secondary replica and sync the logins
    $secondaryInstances | ForEach-Object {
        $secondaryInstanceConnection = Connect-DbaInstance $_ -ClientName $ClientName
        Copy-DbaLogin -Source $primaryInstanceConnection -Destination $secondaryInstanceConnection -ExcludeSystemLogins -WhatIf
    }
}
catch {
    $msg = $_.Exception.Message
    Write-Error "Error while syncing logins for Availability Group '$($AvailabilityGroupName): $msg'"
}

