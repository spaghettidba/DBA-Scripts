
cls

$NetworkCardsBaseKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards"
$BindingsBaseKey = "SYSTEM\CurrentControlSet\Services\Tcpip\Linkage"

$results = @()

$bindings = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine','localhost').OpenSubKey($BindingsBaseKey,$true).GetValue("Bind")

for($i=0;$i-le $bindings.length-1;$i++) { 
	$bindings[$i] = $bindings[$i] -replace "\\Device\\", "" 
	
	$info = @{}
	$info.GUID = $bindings[$i]

	$ConnectionKeyName = "SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}\$($info.GUID)\Connection"
	$info.ConnectionName = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine','localhost').OpenSubKey($ConnectionKeyName).GetValue("Name")
	$info.BindingOrder = $i
	
	[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine','localhost').OpenSubKey($NetworkCardsBaseKey,$true).GetSubKeyNames() | % {
		$keyName = "$NetworkCardsBaseKey\$_"
		
		if([Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine','localhost').OpenSubKey($keyName).GetValue("ServiceName") -eq $info.GUID){
			$info.AdapterName = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine','localhost').OpenSubKey($keyName).GetValue("Description")
		}
	}
	
	$NetworkAdapterInfo = New-Object -TypeName PsObject -Property $info
	
	$results += $NetworkAdapterInfo
}	

$results | Sort BindingOrder | Format-List
