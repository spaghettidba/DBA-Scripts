param(
    [Parameter(Mandatory = $true, Position = 0)] [string]$serverInstance,
	[Parameter(Mandatory = $true, Position = 1)] [Int32]$tcpPort
)

[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
 
##################################################################  
# Function to Enable or Disable a SQL Server Network Protocol 
################################################################## 
function ChangeSQLProtocolStatus($server,$instance,$protocol,$enable,$TcpPort){ 
 
    $smo = 'Microsoft.SqlServer.Management.Smo.' 
    $wmi = new-object ($smo + 'Wmi.ManagedComputer') 
    $singleWmi = $wmi | where {$_.Name -eq $server}   
    $uri = "ManagedComputer[@Name='$server']/ServerInstance[@Name='$instance']/ServerProtocol[@Name='$protocol']" 
	try {
    	$prot = $singleWmi.GetSmoObject($uri) 
	}
	catch{
        throw $_
		return;
	}
    $prot.IsEnabled = $enable 
	if($prot.Name -eq "Tcp") {
		$portToStr = [System.Convert]::toString($TcpPort)
		$prot.IPAddresses["IPAll"].IPAddressProperties["TcpPort"].Value = $portToStr
		$prot.IPAddresses["IPAll"].IPAddressProperties["TcpDynamicPorts"].Value = $( if($portToStr -eq "") { "0" } else { "" } )
	}

    $prot.Alter() 
	
} 



##################################################################  
# Enable TCP/IP SQL Server Network Protocol 
# and set a static port
################################################################## 

$server = $serverInstance.split("\")[0]
$instance = $serverInstance.split("\")[1]
if($instance -eq $null) {
	$instance = "MSSQLSERVER"
}

$server = $env:COMPUTERNAME


try {
    ChangeSQLProtocolStatus -server $server -instance $instance -protocol "Tcp" -enable $true -TcpPort $tcpPort
    ChangeSQLProtocolStatus -server $server -instance $instance -protocol "Np" -enable $false
    try { ChangeSQLProtocolStatus -server $server -instance $instance -protocol "VIA" -enable $false } catch { }
    Write-Output "Network protocol properties set correctly."
} catch {
    throw
}