####################### 
<# 
AddLocalSecurityPolicy.ps1
.SYNOPSIS 
Set policies for SQL Server account
.DESCRIPTION 
Add SQL Server Account to "Lock Pages In Memory" and "Perform Volume Maintenance Tasks" policies
on data and log drives
.INPUTS 
	$serviceAccount - the SQL Server service account
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


function Add-LoginToLocalPrivilege
{
<#
        .SYNOPSIS
Adds the provided login to the local security privilege that is chosen. Must be run as Administrator in UAC mode.
Returns a boolean $true if it was successful, $false if it was not.

.DESCRIPTION
Uses the built in secedit.exe to export the current configuration then re-import
the new configuration with the provided login added to the appropriate privilege.

The pipeline object must be passed in a DOMAIN\User format as string.

This function supports the -WhatIf, -Confirm, and -Verbose switches.

.PARAMETER DomainAccount
Value passed as a DOMAIN\Account format.

.PARAMETER Domain 
Domain of the account - can be local account by specifying local computer name.
Must be used in conjunction with Account.

.PARAMETER Account
Username of the account you want added to that privilege
Must be used in conjunction with Domain

.PARAMETER Privilege
The name of the privilege you want to be added.

This must be one in the following list:
SeManageVolumePrivilege
SeLockMemoryPrivilege

.PARAMETER TemporaryFolderPath
The folder path where the secedit exports and imports will reside. 

The default if this parameter is not provided is $env:USERPROFILE

.EXAMPLE
Add-LoginToLocalPrivilege -Domain "NEIER" -Account "Kyle" -Privilege "SeManageVolumePrivilege"

Using full parameter names

.EXAMPLE
Add-LoginToLocalPrivilege "NEIER\Kyle" "SeLockMemoryPrivilege"

Using Positional parameters only allowed when passing DomainAccount together, not independently.

.EXAMPLE
Add-LoginToLocalPrivilege "NEIER\Kyle" "SeLockMemoryPrivilege" -Verbose

This function supports the verbose switch. Will provide to you several 
text cues as part of the execution to the console. Will not output the text, only presents to console.

.EXAMPLE
("NEIER\Kyle", "NEIER\Stephanie") | Add-LoginToLocalPrivilege -Privilege "SeManageVolumePrivilege" -Verbose

Passing array of DOMAIN\User as pipeline parameter with -v switch for verbose logging. Only "Domain\Account"
can be passed through pipeline. You cannot use the Domain and Account parameters when using the pipeline.

.NOTES
The temporary files should be removed at the end of the script. 

If there is error - two files may remain in the $TemporaryFolderPath (default $env:USERPFORILE)
UserRightsAsTheyExist.inf
ApplyUserRights.inf

These should be deleted if they exist, but will be overwritten if this is run again.

Author:    Kyle Neier
Blog: http://sqldbamusings.blogspot.com
Twitter: Kyle_Neier
#>

    #Specify the default parameterset
    [CmdletBinding(DefaultParametersetName="JointNames", SupportsShouldProcess=$true, ConfirmImpact='High')]
param
    (
[parameter(
Mandatory=$true, 
Position=0,
ParameterSetName="SplitNames")]
[string] $Domain,

[parameter(
Mandatory=$true, 
Position=1,
ParameterSetName="SplitNames"
            )]
[string] $Account,

[parameter(
Mandatory=$true, 
Position=0,
ParameterSetName="JointNames",
ValueFromPipeline= $true
            )]
[string] $DomainAccount,

[parameter(Mandatory=$true, Position=2)]
[ValidateSet("SeManageVolumePrivilege", "SeLockMemoryPrivilege")]
[string] $Privilege,

[parameter(Mandatory=$false, Position=3)]
[string] $TemporaryFolderPath = $env:USERPROFILE
        
)

#Determine which parameter set was used
    switch ($PsCmdlet.ParameterSetName)
{
"SplitNames"
        { 
#If SplitNames was used, combine the names into a single string
            Write-Verbose "Domain and Account provided - combining for rest of script."
            $DomainAccount = "$Domain`\$Account"
        }
"JointNames"
        {
Write-Verbose "Domain\Account combination provided."
            #Need to do nothing more, the parameter passed is sufficient.
        }
}

#Created simple function here so I didn't have to re-type these commands
    function Remove-TempFiles
    {
#Evaluate whether the ApplyUserRights.inf file exists
        if(Test-Path $TemporaryFolderPath\ApplyUserRights.inf)
{
#Remove it if it does.
            Write-Verbose "Removing $TemporaryFolderPath`\ApplyUserRights.inf"
            Remove-Item $TemporaryFolderPath\ApplyUserRights.inf -Force -WhatIf:$false
        }

#Evaluate whether the UserRightsAsTheyExists.inf file exists
        if(Test-Path $TemporaryFolderPath\UserRightsAsTheyExist.inf)
{
#Remove it if it does.
            Write-Verbose "Removing $TemporaryFolderPath\UserRightsAsTheyExist.inf"
            Remove-Item $TemporaryFolderPath\UserRightsAsTheyExist.inf -Force -WhatIf:$false
        }
}

Write-Verbose "Adding $DomainAccount to $Privilege"

    Write-Verbose "Verifying that export file does not exist."
    #Clean Up any files that may be hanging around.
    Remove-TempFiles
    
Write-Verbose "Executing secedit and sending to $TemporaryFolderPath"
    #Use secedit (built in command in windows) to export current User Rights Assignment
    $SeceditResults = secedit /export /areas USER_RIGHTS /cfg $TemporaryFolderPath\UserRightsAsTheyExist.inf

#Make certain export was successful
    if($SeceditResults[$SeceditResults.Count-2] -eq "The task has completed successfully.")
{

Write-Verbose "Secedit export was successful, proceeding to re-import"
        #Save out the header of the file to be imported
        
Write-Verbose "Save out header for $TemporaryFolderPath`\ApplyUserRights.inf"
        
"[Unicode]
Unicode=yes
[Version]
signature=`"`$CHICAGO`$`"
Revision=1
[Privilege Rights]" | Out-File $TemporaryFolderPath\ApplyUserRights.inf -Force -WhatIf:$false
                                    
#Bring the exported config file in as an array
        Write-Verbose "Importing the exported secedit file."
        $SecurityPolicyExport = Get-Content $TemporaryFolderPath\UserRightsAsTheyExist.inf

        #enumerate over each of these files, looking for the Perform Volume Maintenance Tasks privilege
        [Boolean]$isFound = $false
        foreach($line in $SecurityPolicyExport)
{
if($line -like "$Privilege`*")
{
Write-Verbose "Line with the $Privilege found in export, appending $DomainAccount to it"
                            #Add the current domain\user to the list
                            $line = $line + ",$DomainAccount"
                            #output line, with all old + new accounts to re-import
                            $line | Out-File $TemporaryFolderPath\ApplyUserRights.inf -Append -WhatIf:$false
                            
$isFound = $true
            }
}

if($isFound -eq $false)
{
#If the particular command we are looking for can't be found, create it to be imported.
            Write-Verbose "No line found for $Privilege - Adding new line for $DomainAccount"
            "$Privilege`=$DomainAccount" | Out-File $TemporaryFolderPath\ApplyUserRights.inf -Append -WhatIf:$false
        }

#Import the new .inf into the local security policy.
        if ($pscmdlet.ShouldProcess($DomainAccount, "Account be added to Local Security with $Privilege privilege?"))
{
# yes, Run the import:
            Write-Verbose "Importing $TemporaryfolderPath\ApplyUserRighs.inf"
            $SeceditApplyResults = SECEDIT /configure /db secedit.sdb /cfg $TemporaryFolderPath\ApplyUserRights.inf

#Verify that update was successful (string reading, blegh.)
            if($SeceditApplyResults[$SeceditApplyResults.Count-2] -eq "The task has completed successfully.")
{
#Success, return true
                Write-Verbose "Import was successful."
                Write-Output $true
            }
else
            {
#Import failed for some reason
                Write-Verbose "Import from $TemporaryFolderPath\ApplyUserRights.inf failed."
                Write-Output $false
                Write-Error -Message "The import from$TemporaryFolderPath\ApplyUserRights using secedit failed. Full Text Below:
$SeceditApplyResults)"
            }
}
}
else
    {
#Export failed for some reason.
        Write-Verbose "Export to $TemporaryFolderPath\UserRightsAsTheyExist.inf failed."
        Write-Output $false
        Write-Error -Message "The export to $TemporaryFolderPath\UserRightsAsTheyExist.inf from secedit failed. Full Text Below:
$SeceditResults)"
        
}

Write-Verbose "Cleaning up temporary files that were created."
    #Delete the two temp files we created.
    Remove-TempFiles
    
}





Add-LoginToLocalPrivilege $serviceAccount "SeManageVolumePrivilege"
Add-LoginToLocalPrivilege $serviceAccount "SeLockMemoryPrivilege"
