####################### 
<# 
DiskPermissions.ps1
.SYNOPSIS 
Changes disk top level permissions
.DESCRIPTION 
Removes Everyone from non system drives and adds full control permissions
on data and log drives
.INPUTS 
	$serviceAccount - the SQL Server service account
	$disk - the disk to process
.OUTPUTS 
   No output
.EXAMPLE 
Version History 
v1.0   - Gianluca Sartori - Initial release 
#> 

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True,Position=0)] [string]$serviceAccount
)



$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None
$objType = [System.Security.AccessControl.AccessControlType]::Allow 


GET-WMIOBJECT –query “SELECT * from win32_logicaldisk where DriveType = '3'” | Select DeviceId | % {

	$disk = $_.DeviceId + "\" 
	
	if(-not ($disk -eq "C:\")) {
		
		$folder = $disk
		$Acl = Get-Acl $folder
		$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($serviceAccount,"FullControl", $InheritanceFlag, $PropagationFlag, $objType)
		$Acl.SetAccessRule($Ar)
		Set-Acl $folder $Acl


		$everyone = 'Everyone' 
		$acls = Get-Acl -path $folder
		$outputObject = @() 

		Foreach($acl in $acls) 
		{ 
			$folder = (convert-path $acl.pspath) 
		  
			Foreach($access in $acl.access) 
			{ 
		    	Foreach($value in $access.identityReference.Value) 
		     	{ 
			       	if ($value -eq $everyone) 
			        { 
		           		$acl.RemoveAccessRule($access) | Out-Null 
		          	} 
		     	} #end foreach value 
		  	} # end foreach access 
		 	Set-Acl -path $folder -aclObject $acl 
			$i++ 
		} #end Foreach acl
		
	 } # if not C:\
	
} # end Foreach Disk