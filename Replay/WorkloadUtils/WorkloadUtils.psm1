<#
    Global scoped variables
#>
# System line separator
$global:newline = [Environment]::NewLine

# Quote char
$global:quote = "`""



<#
    Module scoped variables
#>
# Path to current executing script
$script:script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Path to Powershell executable
$script:posh_path = (Get-Command "Powershell").get_Path()

$script:ErrorTrcFileName = ""
$script:ErrorTrcFileNameNoExt = "Errors"
$script:RMLTrcFileName = ""
$script:RMLTrcFileNameNoExt = "RML"

$global:RMLUtilsInstallPath = "C:\Program Files\Microsoft Corporation\RMLUtils\"
$script:ostressPath         = Join-Path $global:RMLUtilsInstallPath "ostress.exe"  #Path to Ostress executable
$script:OstressSettingsFile = Join-Path $global:RMLUtilsInstallPath "sample.ini"   #Path to Ostress settings file
$script:readtracePath       = Join-Path $global:RMLUtilsInstallPath "readtrace.exe" #Path to readtrace executable


Class SQLServerInstance {
    # Name of the SQL Server instance i.e.: SERVER42\INSTANCE01
    [String]$Name
    # Name of the server, without the instance i.e.: SERVER42
    [String]$ComputerName
    # Name of the physical host (can be different from server name in clusters)
    # i.e. CLUSTERHOST31
    [String]$MachineName
    # Name of the instance i.e.: INSTANCE01
    [String]$InstanceName
    # SID of the instance i.e.: MSSQL for default instances, instance name for named instances
    [String]$InstanceSID
    # Name of the performance counter instance
    [String]$CounterName
    # Is it part of a cluster?
    [bool]$IsClustered

    SQLServerInstance([String]$Name){
        $this.Name = $Name

        if ($Name.Contains("\")) {
            $srvr = $Name.Split("\")
            $this.ComputerName = $srvr[0]
            if(($this.ComputerName -ieq "(local)") -or ($this.ComputerName -eq ".")) {
                $this.ComputerName = $env:COMPUTERNAME
                $this.MachineName = $env:COMPUTERNAME
            }
            $this.InstanceName = $srvr[1]
            $this.CounterName = $this.ComputerName +"_"+ $this.InstanceName
            $this.InstanceSID ="MSSQL$" + $this.InstanceName
        }
        else {
              $this.ComputerName = $Name
            $this.InstanceName = ""
            $this.CounterName = $Name
            $this.InstanceSID = "SQLServer"
        }
        try {
            $this.LoadServerProperties()
        }
        catch {
            $this.MachineName = $null
            $this.IsClustered = $null
        }
    }


    [void] LoadServerProperties() {
        $sql = "SELECT SERVERPROPERTY('ComputerNamePhysicalNetbios') AS MachineName, SERVERPROPERTY('IsClustered') AS IsClustered"
        $info = Invoke-sqlcmd -Query $sql -ServerInstance $this.Name -Database master
        $this.MachineName = $info.MachineName
        $this.IsClustered = $info.IsClustered
    }


    <#
        Checks whether current user is able to connect to the remote server
    #>
    [bool] IsAvailable() {  
        [bool]$status = $false

        if(Test-Connection $this.ComputerName -Count 1 -ErrorAction SilentlyContinue) {
            try {
                if(New-PSDrive -Name testshare -PSProvider FileSystem -Root "\\$($this.MachineName)\c$" -ErrorAction SilentlyContinue) {  
                    Write-Debug "$($this.ComputerName) Online and able to connect"
                    $status = $true
                }
                else {
                    Write-Debug "$($this.ComputerName) Online but unable to connect as admin"
                    $status = $false
                }
            }
            finally {
                try {
                    Remove-PSDrive testshare
                }
                catch {
                    # ignore
                }
            }
        }
        else {
            Write-Debug "$($this.ComputerName) Offline / Not in DNS."
            $status = $false
        }

        return $status
    }
} # / class


<#
    Start Workload Capture 
#>
function Start-WorkloadCapture {
    [CmdletBinding()]
    Param(
      # Specifies the server where the workload is captured
      [Parameter(Mandatory=$True,Position=1)]
      [SQLServerInstance]$Server,
      
      # Specifies where to store the trace files on the server
      # The path is relative to the server's filesystem
      [Parameter(Mandatory=$True,Position=2)]
      [string]$TracePath,
      
      # Array of string filters for the trace template
      # This script uses the default RML capture trace template
      # If you want to add more filters, you cann specify here a list
      # of filters by using the syntax
      # exec sp_trace_setfilter @TraceID, [column], [logical_operator], [comparison_operator], [value]
      # @TeaceID is fixed and is part of the script the filters will be injected in.
      # EXAMPLE:
      # ---------------
      # exec sp_trace_setfilter @TraceID, 11, 1, 0, N'GESUser_LabViewELEUser'
      [Parameter(Mandatory=$False,Position=3)]
      [string[]]$TraceFilters
    )
    Process {

        # Check permissions. The script needs administrator permissions on the server
        if(-not $Server.IsAvailable()){
            Throw "Server $($Server.ComputerName) is unavailable. Make sure the server is online and you have administrator permissions."
        }
        
        # Start the perfmon counters
        Start-PerformanceDataCollection -TargetServer $Server -OutputFolder $TracePath

        # Start the traces
        Start-Traces -TargetServer $Server -OutputFolder $TracePath -TraceFilters $TraceFilters  
    }
}




function Invoke-WorkloadCapture {
    [CmdletBinding()]
    Param(
      # Specifies the server where the workload is captured
      [Parameter(Mandatory=$True,Position=1)]
      [string]$ServerName,

      # Specifies where to store the trace files on the server
      # The path is relative to the server's storage      
      [Parameter(Mandatory=$True,Position=2)]
      [string]$ServerOutputPath,

      # Trace filters, if any
      [Parameter(Mandatory=$False,Position=3)]
      [string[]]$TraceFilters,

      # Output path for the workload files analysis
      [Parameter(Mandatory=$True,Position=4)]
      [string]$OutputPath,

      # Name of the capture, a label that you can use 
      # to identify different captures
      [Parameter(Mandatory=$False,Position=5)]
      [string]$CaptureName  = "CAPTURE",

      # String that specifies which databases to back up
      # during the workload capture. 
      # It can be either 
      # 1. **USER** - all user databases
      # 2. **ALL**  - all databases
      # 3. <DatabaseName> - The specific database
      # 4. <Empty>  - no database
      [Parameter(Mandatory=$False,Position=6)]
      [string]$BackupDatabases = "",

      # Duration of the workload capture in minutes
      [Parameter(Mandatory=$False,Position=7)]
      [int]$DurationMinutes = -1,

      # Name of the replay job to wait on
      [Parameter(Mandatory=$False,Position=8)]
      [string]$ReplayJob = "",

      [Parameter(Mandatory=$False,Position=9)]
      [bool]$ProcessRMLFiles = $true
    )
    Process {
        <#
            1. Start
            2. Copy trace files while produced
            3. Stop
            4. Copy leftover files
        #>

        # Validate input 
        if(($DurationMinutes -eq -1) -and ($ReplayJob -eq "")) {
            throw 'Invalid parameters specified. $ReplayJob or $DurationMinutes must be specified'
            return
        }

        # Inizialize some local variables 
        [SQLServerInstance]$Server = [SQLServerInstance]::new($ServerName)

        # Inizialize local paths
        [string]$local_perfdata = $OutputPath
        If (-not (Test-Path $local_perfdata)) { New-Item $local_perfdata -ItemType directory | Out-Null }
        If (-not (Test-Path $local_perfdata\$CaptureName)) { 
            New-Item $local_perfdata\$CaptureName -ItemType directory | Out-Null 
        }
        else {
            Get-ChildItem $local_perfdata\$CaptureName | Where { -not ($_.BaseName -eq "ostress_output") } | % {
                Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
        If (-not (Test-Path $local_perfdata\$CaptureName\Trace)) { New-Item $local_perfdata\$CaptureName\Trace -ItemType directory | Out-Null }
        If (-not (Test-Path $local_perfdata\$CaptureName\Backup)) { New-Item $local_perfdata\$CaptureName\Backup -ItemType directory | Out-Null }
        
        Write-Verbose "Output will be saved in $local_perfdata"

        # Start the workload capture (traces and perfmon)
        Start-WorkloadCapture `
            -Server $Server `
            -TracePath $ServerOutputPath `
            -TraceFilters $TraceFilters

        # Start a job that takes care of moving trace files 
        # from the server path to the local path 
        Move-TraceFiles $Server $ServerOutputPath $local_perfdata

        # Take a backup of all specified databases
        if($BackupDatabases -ne "") {
            Backup-Databases $Server $BackupDatabases "$ServerOutputPath\Backup" "$local_perfdata\$CaptureName\Backup" $false 
        }

        if($DurationMinutes -ge 0) {
            # Wait for the set duration of the workload 
            for($i=0;$i -lt ($DurationMinutes * 60); $i++){
                Write-Progress -Activity "Capturing Workload..." `
                    -Status "$([int]($i / 60)) minutes captured." `
                    -SecondsRemaining (($DurationMinutes * 60) - $i) `
                    -PercentComplete (($i / ($DurationMinutes * 60)) * 100)  
                Start-Sleep -Seconds 1
            }
            Write-Progress -Activity "Capturing Workload..." -Completed  
        }

        if($ReplayJob -ne "") {
            # Wait for the replay job to end
            $ostress_job = Get-Job -Name $ReplayJob 
            $ostress_job | % { Receive-Job -Job $_ -Wait -WriteEvents -AutoRemoveJob } 
        }

        Write-Verbose "Workload capture complete."
        
        Get-Job -Name "TraceCopyJob" | Stop-Job | Out-Null
        Get-Job -Name "TraceCopyJob" | Remove-Job -Force  | Out-Null
    

        Stop-WorkloadCapture `
            -TargetServer $Server `
            -CaptureName $CaptureName `
            -OutputFolder $local_perfdata `
            -RemoteOutputFolder $ServerOutputPath `
            -ProcessRMLFiles $ProcessRMLFiles `
            -FilterDatabase $BackupDatabases

    }

}


# Checks whether $Path is UNC or not.
# If not, it prepends the administrative share prefix
function Get-UNCPath([string]$MachineName, [string]$Path){
    if($Path.StartsWith("\\")) {
        $UncPath = $Path
    }
    else {
        $UncPath = "\\" + $MachineName + "\" + ($Path -replace ":", "$")
    }
    return $UncPath
}

function Get-RMLMaximumSupportedTraceVersion() {
    [string]$ProductVersion = ""
    [string]$FileVersionInfo = (Get-ItemProperty $script:readtracePath).VersionInfo
    $SplitInfo = $FileVersionInfo.Split([char]13)
    foreach ($Item in $SplitInfo) {
        $Property = $Item.Split(":").Trim()
        if ($Property[0] -eq "ProductVersion") {
            $ProductVersion = $Property[1]
        }
    }
    $pv = $ProductVersion.Split(".")
    if($pv[0] -eq "8") {
        return 8 #SQL Server 2000
    }
    else {
        if($pv[1] -eq "00") {
            return 9 # SQL Server 2005
        }
        elseif($pv[1] -eq "01") {
            return 10 #SQL Server 2008/2008 R2
        }
        elseif($pv[1] -eq "04") {
            return 12 # SQL Server 2014
        }
    }
    return 0 # version not identified 
}


function Convert-TraceFile([string]$TracePath){
    # The version information we want to write: 0x0A = 10 = SQLServer 2008
    [Byte[]] $versionData = Get-RMLMaximumSupportedTraceVersion
    # The offset of the version information in the file
    $offset = 390
    
    [System.IO.FileMode] $open = [System.IO.FileMode]::OpenOrCreate
    $stream = New-Object System.IO.FileStream -ArgumentList $TracePath, $open
    $stream.Seek($offset, [System.IO.SeekOrigin]::Begin) | out-null
    $stream.Write($versionData, 0, $versionData.Length)
    $stream.Close()
}


function Write-DbidMappings([string]$ServerName, [string]$OutputPath){
    [string] $sql = "SELECT database_id, name FROM sys.databases;"
    [string[]] $outputData = @()

    $dbs = Invoke-sqlcmd -Query $sql -ServerInstance $ServerName -Database master
    $dbs | % {
        $str = ""
        $str += $_.database_id
        $str += ","
        $str += $_.name
        $outputData += $str
    }

    $UCSEncoding = New-Object System.Text.UnicodeEncoding
    [System.IO.File]::WriteAllLines("$OutputPath\dbid_map.txt", $outputData , $UCSEncoding)
}

function Move-TraceFiles([SQLServerInstance]$TargetServer, [string]$RemotePath, [string]$LocalPath) {

    $UncPath = Get-UNCPath $TargetServer.MachineName $RemotePath
    # CREATE LOCAL BACKUP PATH IF NEEDED 
    If (-Not (Test-Path $LocalPath)) { New-Item $LocalPath -ItemType Directory | Out-Null }

    Start-Job -ScriptBlock { 
            While ($true) {
                Get-ChildItem $uncPath -Filter *.trc | % {
                    try { 
                        Move-Item $_ $LocalPath
                    }
                    catch {
                        ## ignore
                    }
                    Start-Sleep -Seconds 5
                }
                Start-Sleep -Seconds 5
            } 
        } -Name "TraceCopyJob" | Out-Null
    
}



function Backup-Databases([SQLServerInstance]$TargetServer, [string]$DatabaseNames, [string]$OutputPath, [string]$localPath, [bool]$Asynchronous) {

    # CREATE REMOTE BACKUP PATH IF NEEDED
    $remotePath = Get-UNCPath $TargetServer.MachineName $OutputPath
    If (-Not (Test-Path $remotePath)) { New-Item $remotePath -ItemType Directory | Out-Null }

    [string]$sql = "SELECT name FROM sys.databases "

    if($DatabaseNames -eq "**ALL**") {
        $sql += " WHERE 1 = 1 "
    }
    elseif($DatabaseNames -eq "**USER**") {
        $sql += " WHERE name NOT IN ('master','model','msdb','tempdb','distribution') "
    }
    elseif($DatabaseNames -eq "") {
        $sql += " WHERE 1 = 2 "
    }
    else {
        $sql += " WHERE name = '$DatabaseNames' "
    }

    $dbs = Invoke-sqlcmd -Query $sql -ServerInstance $TargetServer.Name -Database master

    $sb = {
        param([string]$Server, [string]$DatabaseName, [string]$OutputPath, [string]$UNCPath, [string]$LocalPath)
        
        [string]$sql = "BACKUP DATABASE [$databaseName] TO DISK = '$OutputPath\$databaseName.bak' WITH INIT, COPY_ONLY;"
        Write-Host "Backing up database $databaseName to file $OutputPath\$databaseName.bak"
        try {
            Invoke-sqlcmd -Query $sql -ServerInstance $Server -Database master -QueryTimeout 65535 | out-null
            Write-Host "Backup of database $databaseName completed successfully"
            Write-Host "Moving $UNCPath to $localPath" 
            Move-Item -Path $UNCPath -Destination $localPath\$databaseName.bak
        }
        catch {
            Write-Error $_.Message
            Throw $_
        } 
    }

    $dbs | % {
        # Start each backup in a separate job
        [string]$currentDatabaseName = $_.Name
        $env:CurrentModule = $script:script_path
        $UNCPath = Get-UNCPath $TargetServer.MachineName "$OutputPath\$currentDatabaseName.bak"
        $args_list = @($TargetServer.Name, $currentDatabaseName, $OutputPath, $UNCPath, $localPath)
        if($Asynchronous) {
            $jobs += Start-Job -ScriptBlock $sb -ArgumentList $args_list
        }
        else {
            Invoke-Command $sb -ArgumentList $args_list
        }
    }
    if($Asynchronous) {
        Receive-Job -Job $jobs -Wait -WriteEvents -AutoRemoveJob
    }
}




function Restore-Databases {
    [CmdletBinding()]
    Param(
      # Server where to perform the restore
      [Parameter(Mandatory=$True,Position=1)]
      [SQLServerInstance]$TargetServer,

      # Name of databases to restore    
      [Parameter(Mandatory=$True,Position=2)]
      [string]$DatabaseNames,

      # Output path, relative to the server
      [Parameter(Mandatory=$False,Position=3)]
      [string]$ServerPath,

      # Output path, relative to the client
      [Parameter(Mandatory=$True,Position=4)]
      [string]$LocalPath,

      [Parameter(Mandatory=$False,Position=5)]
      [string]$PostRestoreScript = "",

      [Parameter(Mandatory=$False,Position=6)]
      [bool]$KeepReplication = $false,

      [Parameter(Mandatory=$False,Position=7)]
      [bool]$Asynchronous = $false
      
    )
    Process {

        # CREATE REMOTE BACKUP PATH IF NEEDED
        $remotePath = Get-UNCPath $TargetServer.MachineName $ServerPath
        If (-Not (Test-Path $remotePath)) { New-Item $remotePath -ItemType Directory | Out-Null }

        $sb = {
            param([string]$ServerName, [string]$DatabaseName, [string]$ServerPath, [string]$UNCPath, [string]$LocalPath, [string]$PostRestoreScript, [bool]$KeepReplication)
        
            [string]$sqlDrop = "
                IF DB_ID('$databaseName') IS NOT NULL 
                BEGIN
                    ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; 
                    DROP DATABASE [$databaseName];
                END";
            Write-Host "Restoring database $databaseName from file $ServerPath\$databaseName.bak"
            try {
                Write-Host "Copying $localPath\$databaseName.bak to $UNCPath"
                Copy-Item -Path "$localPath\$databaseName.bak" -Destination $UNCPath
                Invoke-sqlcmd -Query $sqlDrop -ServerInstance $ServerName -Database master -QueryTimeout 65535 | out-null

                $server = new-object Microsoft.SqlServer.Management.Smo.Server $ServerName

                $dataFolder = $server.Settings.DefaultFile
                $logFolder = $server.Settings.DefaultLog

                if ($dataFolder.Length -eq 0) {
                    $dataFolder = $server.Information.MasterDBPath
                }

                if ($logFolder.Length -eq 0) {
                    $logFolder = $server.Information.MasterDBLogPath
                }

                $backupDeviceItem = new-object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $ServerPath\$databaseName.bak, 'File'

                $restore = new-object 'Microsoft.SqlServer.Management.Smo.Restore'
                $restore.Database = $DatabaseName
                $restore.Devices.Add($backupDeviceItem)

                $dataFileNumber = 0

                foreach ($file in $restore.ReadFileList($server)) 
                {
                    $relocateFile = new-object 'Microsoft.SqlServer.Management.Smo.RelocateFile'
                    $relocateFile.LogicalFileName = $file.LogicalName

                    if ($file.Type -eq 'D') {
                        if($dataFileNumber -ge 1) {
                            $suffix = "_$dataFileNumber"
                        }
                        else {
                            $suffix = $null
                        }
                        $relocateFile.PhysicalFileName = "$dataFolder\$DatabaseName$suffix.mdf"
                        $dataFileNumber ++
                    }
                    else {
                        $relocateFile.PhysicalFileName = "$logFolder\$DatabaseName.ldf"
                    }
                    $restore.RelocateFiles.Add($relocateFile) | out-null
                }    

                if($KeepReplication) {
                    $restore.KeepReplication = $True    
                }
                $restore.SqlRestore($server);

                Write-Host "Restore of database $databaseName completed successfully."

                if($PostRestoreScript -ne "") {
                    Write-Host "Restore of database $databaseName completed successfully"
                    Invoke-sqlcmd -Query $PostRestoreScript -ServerInstance $ServerName -Database $databaseName -QueryTimeout 65535 | out-null
                }
            }
            catch {
                Write-Error $_.Message
                Throw $_
            } 
        } # /scriptblock


        if($DatabaseNames -eq "**USER**") {
            $dbs = Get-ChildItem -Path $localPath | Where { -not(($_.Name -eq "master") -or ($_.Name -eq "model") -or ($_.Name -eq "msdb"))}    
        }
        elseif($DatabaseName -eq "**ALL**") {
            $dbs = Get-ChildItem -Path $localPath
        }
        else {
            $dbs = Get-ChildItem -Path $localPath -Filter $DatabaseNames.bak
        }
        $dbs | % {
            # Start each restore in a separate job
            [string]$currentDatabaseName = $_.BaseName
            $env:CurrentModule = $script:script_path
            $UNCPath = Get-UNCPath $TargetServer.MachineName "$ServerPath\$currentDatabaseName.bak"
            $arg_list = @($TargetServer.Name, $currentDatabaseName, $ServerPath, $UNCPath, $localPath, $PostRestoreScript, $KeepReplication)

            if($Asynchronous) {
                # Asynchronous
                $jobs += Start-Job -ScriptBlock $sb `
                    -ArgumentList $arg_list
            }
            else {
                # Synchronous
                Invoke-Command $sb -ArgumentList $arg_list 
            }
        }
        if($Asynchronous) {
            Receive-Job -Job $jobs -Wait -WriteEvents -AutoRemoveJob
        }
    }
}


function wrapProcess([String]$name, [String[]]$arguments){
      $process = New-Object System.Diagnostics.Process
      $setup = $process.StartInfo
      $setup.FileName = $name
      $setup.Arguments = [String]::Join(" ", $arguments)
      $setup.WorkingDirectory = $script_path
      $setup.UseShellExecute = $false
      $setup.RedirectStandardError = $true
      $setup.RedirectStandardOutput = $true
      $setup.RedirectStandardInput = $false
      $setup.CreateNoWindow = $true
      # Hook into the standard output and error stream events
      $errEvent = Register-ObjectEvent -InputObj $process `
            -Event "ErrorDataReceived" `
            -Action `
            {
                  param
                  (
                        [System.Object] $sender,
                        [System.Diagnostics.DataReceivedEventArgs] $e
                  )
                  Write-Verbose -foreground "DarkRed" $e.Data
            }
      $outEvent = Register-ObjectEvent -InputObj $process `
            -Event "OutputDataReceived" `
            -Action `
            {
                  param
                  (
                        [System.Object] $sender,
                        [System.Diagnostics.DataReceivedEventArgs] $e
                  )
                  Write-Verbose $e.Data
            }
      # Start the process
      [Void] $process.Start()
      # Begin async read events
      $process.BeginOutputReadLine()
      $process.BeginErrorReadLine()
      # Wait until process exit
      while (!$process.HasExited)
      {
            Start-Sleep -Milliseconds 100
      }
      # Shutdown async read events
      $process.CancelOutputRead()
      $process.CancelErrorRead()
      $process.Close()

}


function Start-PerformanceDataCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=1)]
        [SQLServerInstance]$TargetServer,
        [Parameter(Mandatory=$True, Position=2)]
        [string]$OutputFolder
    )  
    Process {

        $script_path = $script:script_path
        $cntrname = $TargetServer.CounterName
        $server = $TargetServer.MachineName
        $sqlinstance = $TargetServer.InstanceSID


        #logman arguments
        $logman_arguments = "create counter $cntrname -s $server -si 00:00:15 -cf $env:temp\$cntrname.txt --v -f bin -o $OutputFolder\$cntrname -rf 168:00:00"
        $logman_start_arguments = "start $cntrname -s $server"
        $logman_stop_arguments = "stop $cntrname -s $server"
       $logman_delete_arguments = "delete $cntrname -s $server"

        Write-Verbose "Starting a new perfmon capture using PAL template."

        # Stop the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_stop_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 
        
        # Delete the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_delete_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 
        
        #delete the perfmon blg file
        $remotePerfFileName = Get-UNCPath $TargetServer.MachineName ($OutputFolder + "\" + $cntrname + "*.blg")
        
        If (Test-Path $remotePerfFileName) { Remove-Item $remotePerfFileName -re -ErrorAction SilentlyContinue }

        #Read counters definition
        $arr_counters = Get-Content $script_path\counters.txt
        $arr_counters | % {$_ -replace "<HOSTNAME>", "\\$($TargetServer.ComputerName)"} | % {$_ -replace "<INSTANCE>", $sqlinstance} | Set-Content $env:temp\$cntrname.txt
        
        # Create the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 

        # Start the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_start_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 
        
    } # / Process

}



function Start-Traces {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=1)]
        [SQLServerInstance]$TargetServer,
        [Parameter(Mandatory=$True, Position=2)]
        [string]$OutputFolder,
        [Parameter(Mandatory=$False, Position=3)]
        [string[]]$TraceFilters
    )  
    Process {
        Write-Verbose "Starting sql trace."
        $ErrorTrcFileName = $OutputFolder + "\" + $script:ErrorTrcFileNameNoExt
        $RMLTrcFileName = $OutputFolder + "\" + $script:RMLTrcFileNameNoExt

        # STOP THE EXISTING ERROR TRACE
        Invoke-sqlcmd -InputFile $script:script_path\stopTrace.sql -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$ErrorTrcFileName -QueryTimeout 65535

        $remoteTrcFileName = Get-UNCPath $TargetServer.MachineName (($ErrorTrcFileName -replace ":", "$") + ".trc")
        $remoteTrcFolder = (Split-Path $remoteTrcFileName)

        # MAKE SURE REMOTE PATH EXISTS
        If(-Not (Test-Path $remoteTrcFolder)) { New-Item -Path $remoteTrcFolder -ItemType Directory}

        # DELETE ANY REMOTE ERROR TRACE FILE
        get-childitem $remoteTrcFolder -Filter $script:ErrorTrcFileNameNoExt*.trc | Remove-Item -ErrorAction SilentlyContinue

        #START THE NEW ERROR TRACE
        $info = Invoke-sqlcmd -InputFile $script:script_path\startErrorTrace.sql -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$ErrorTrcFileName -QueryTimeout 65535
        
        #STOP THE EXISTING RML TRACE
        Invoke-sqlcmd -InputFile $script:script_path\stopTrace.sql -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$RMLTrcFileName -QueryTimeout 65535

        #DELETE THE REMOTE RML TRACE FILE
        $remoteTrcFileName = $remoteTrcFolder + "\" + $script:RMLTrcFileNameNoExt + ".trc"
        get-childitem $remoteTrcFolder -Filter $script:RMLTrcFileNameNoExt*.trc | Remove-Item -ErrorAction SilentlyContinue
        
        #BUILD THE RML TRACE DEFINITION
        $filters = ""
        $TraceFilters | 
            ForEach-Object {
                $filters += $($_ + $global:newline)
            }
            
        $query = ""
        Get-Content $script:script_path\startRMLTrace.sql | 
            ForEach-Object {
                $query += $($_ + $global:newline)
            }
            
        $pattern = "\`$\(TraceFilters\)"
        $query = $query -replace $pattern, $filters
            
        $info = Invoke-sqlcmd -Query $query -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$RMLTrcFileName -QueryTimeout 65535
    } # / Process

}


function Stop-WorkloadCapture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=1)]
        [SQLServerInstance]$TargetServer,
        [Parameter(Mandatory=$True, Position=2)]
        [String]$CaptureName, # BASELINE / COMPARE
        [Parameter(Mandatory=$True, Position=3)]
        [String]$OutputFolder, # LOCAL PERFDATA
        [Parameter(Mandatory=$True, Position=4)]
        [String]$RemoteOutputFolder, # REMOTE PERFDATA
        [Parameter(Mandatory=$True, Position=5)]
        [bool]$ProcessRMLFiles, # Process RML files?
        [Parameter(Mandatory=$False, Position=6)]
        [String]$FilterDatabase = "" #Filter Database
    )
    Process {

        Write-Verbose "Stopping data collection $($TargetServer.CounterName) ."
        
        $logman_stop_arguments = "stop $($TargetServer.CounterName) -s $($TargetServer.MachineName)"
        $logman_delete_arguments = "delete $($TargetServer.CounterName) -s $($TargetServer.MachineName)"

        # Stop the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_stop_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 
        
        # Delete the collection set
        $strCMD = $ExecutionContext.InvokeCommand.ExpandString($logman_delete_arguments)
        wrapProcess "C:\Windows\System32\logman.exe" @($strCMD) 
        
        Write-Verbose "Copying performance data."
        #copy performance data to the local path
        $remotePerfFileName = Get-UNCPath $TargetServer.MachineName ($RemoteOutputFolder + "\" + $TargetServer.CounterName + "*.blg")
        Copy-Item $remotePerfFileName -Destination $($OutputFolder +"\"+ $CaptureName) 

        #delete the perfmon blg files
        Remove-Item $remotePerfFileName -ErrorAction SilentlyContinue

        #STOP THE EXISTING TRACES
        Write-Verbose "Stopping sql traces."
        $ErrorTrcFileName = $RemoteOutputFolder + "\" + $ErrorTrcFileNameNoExt
        $RMLTrcFileName = $RemoteOutputFolder + "\" + $RMLTrcFileNameNoExt
        Invoke-sqlcmd -InputFile $script:script_path\stopTrace.sql -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$script:ErrorTrcFileNameNoExt -QueryTimeout 65535
        Invoke-sqlcmd -InputFile $script:script_path\stopTrace.sql -ServerInstance $TargetServer.Name -Database master -Variable TraceFileName=$script:RMLTrcFileNameNoExt -QueryTimeout 65535


        #copy the trace file to the local path
        Write-Verbose "Copying trace files."
        $RemoteTraceFolder = Get-UNCPath $TargetServer.MachineName $RemoteOutputFolder

        if($RemoteTraceFolder.StartsWith('\\')) {
            Write-Verbose "Setting permissions on the trace files..."
            $current_username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $sql = "
                DECLARE @cmdshell bit = CAST((
                    SELECT value
                    FROM sys.configurations
                    WHERE name = 'xp_cmdshell'
                ) AS bit)

                IF @cmdshell = 0
                BEGIN
                    EXEC sp_configure 'advanced', 1
                    RECONFIGURE
                    EXEC sp_configure 'xp_cmdshell', 1
                    RECONFIGURE
                END


                DECLARE @cmd varchar(500) 
                SET @cmd = 'CACLS `"$RemoteTraceFolder\*.trc`" /E /G $($current_username):F'
                EXEC xp_cmdshell @cmd


                IF @cmdshell = 0
                BEGIN
                    EXEC sp_configure 'xp_cmdshell', 0
                    RECONFIGURE
                END
            "
            Invoke-Sqlcmd -ServerInstance $TargetServer.Name -Database master -QueryTimeout 65535 -Query $sql
        }

        Start-Sleep -Seconds 2

        get-childitem $RemoteTraceFolder -Filter $script:ErrorTrcFileNameNoExt*.trc | 
            Move-Item -Destination $($OutputFolder +"\"+ $CaptureName + "\Trace")

        get-childitem $RemoteTraceFolder -Filter $script:RMLTrcFileNameNoExt*.trc | 
            Move-Item -Destination $($OutputFolder +"\"+ $CaptureName + "\Trace")

        Write-Verbose "Converting TraceFile."
        Get-ChildItem $OutputFolder\$CaptureName\Trace -Filter $script:RMLTrcFileNameNoExt*.trc | % {
            Convert-TraceFile $_.FullName
        }

        if(-not (Test-Path "$OutputFolder\$CaptureName\ReadTrace_output")) {
            New-Item "$OutputFolder\$CaptureName\ReadTrace_output" -ItemType Directory | Out-Null
        }

        Write-Verbose "Invoking ReadTrace."

        if(-not $ProcessRMLFiles) { $processRML = '-f' }

        $readTraceArgs = @(
                "-o$OutputFolder\$CaptureName\ReadTrace_output",
                "-I$OutputFolder\$CaptureName\Trace\rml.trc",
                "-E",
                "-S(local)",
                "-dPerfAnalysis_$CaptureName",
                "-T18",
                "$processRML"
            ) 

	if($FilterDatabase -ne "") {
		$readTraceArgs += "-C`"$FilterDatabase`""
	}

        &$script:readtracePath $readTraceArgs

        Write-Verbose "ReadTrace process ended."

        Write-Verbose "Creating database mappings."
        Write-DbidMappings $TargetServer.Name "$OutputFolder\$CaptureName\ReadTrace_output" 

        Write-Verbose "Importing BLG files into ReadTrace database"

        [string]$sqlCleanup = "
            IF OBJECT_ID('DisplayToID') IS NOT NULL 
                TRUNCATE TABLE [DisplayToID]
            IF OBJECT_ID('CounterData') IS NOT NULL 
                TRUNCATE TABLE [CounterData]
            IF OBJECT_ID('CounterDetails') IS NOT NULL 
                TRUNCATE TABLE [CounterDetails]
        "
        Invoke-Sqlcmd -Query $sqlCleanup -ServerInstance "(local)" -Database "PerfAnalysis_$CaptureName" | Out-Null

        $sqlDsnConnection = "SQL:$CaptureName!PerfAnalysis_$CaptureName"
        CreateSystemDSN "$CaptureName" "(local)" "PerfAnalysis_$CaptureName" $false
         
        $relogArgs = @("$OutputFolder\$CaptureName\*.blg","-f","SQL","-o",$sqlDsnConnection)
        &relog.exe $relogArgs

        RemoveSystemDSN "PerfAnalysis_$CaptureName" $false
        
    } # / Process
}



function Invoke-WorkloadReplay {
    [CmdletBinding()]
    Param(
      # Specifies the server where the workload must be replaid
      [Parameter(Mandatory=$True,Position=1)]
      [string]$ServerName,

      # Path of the RML files to replay      
      [Parameter(Mandatory=$True,Position=2)]
      [string]$RMLInputFiles,

      # Specifies where to store the trace files on the server
      # The path is relative to the server's storage      
      [Parameter(Mandatory=$True,Position=3)]
      [string]$ServerOutputPath,

      # Trace filters, if any
      [Parameter(Mandatory=$False,Position=4)]
      [string[]]$TraceFilters,

      # Output path for the workload files analysis
      [Parameter(Mandatory=$True,Position=5)]
      [string]$OutputPath,

      # Name of the capture, a label that you can use 
      # to identify different captures
      [Parameter(Mandatory=$False,Position=6)]
      [string]$CaptureName  = "REPLAY",

      # String that specifies which databases to restore
      # during the workload capture. 
      # It can be either 
      # 1. **USER** - all user databases
      # 2. **ALL**  - all databases
      # 3. <DatabaseName> - The specific database
      # 4. <Empty>  - no database
      [Parameter(Mandatory=$False,Position=7)]
      [string]$RestoreDatabases = "",

      [Parameter(Mandatory=$False,Position=8)]
      [bool]$KeepReplication = $false,

      # Path to the backup files to restore
      [Parameter(Mandatory=$False,Position=9)]
      [string]$RestoreSourcePath = "",

      [Parameter(Mandatory=$true,Position=10)]
      [string]$OstressSettingsFile,

      [Parameter(Mandatory=$false,Position=11)]
      [string]$PostRestoreScript = ""
    )
    Process {

        [SQLServerInstance]$Server = [SQLServerInstance]::new($ServerName)

        if($RestoreDatabases -ne "") { 
            Restore-Databases -TargetServer $Server -DatabaseNames $RestoreDatabases -ServerPath $ServerOutputPath -LocalPath $RestoreSourcePath -PostRestoreScript $PostRestoreScript -Asynchronous $False 
        }

        If (-not (Test-Path "$OutputPath\$CaptureName")) { mkdir "$OutputPath\$CaptureName" -Force | Out-Null }
        If (-not (Test-Path "$OutputPath\$CaptureName\ostress_output")) { mkdir "$OutputPath\$CaptureName\ostress_output" -Force -ErrorAction SilentlyContinue | Out-Null }

        [string]$ReplayJob = "Replay_" + [guid]::NewGuid()
        
        $sb = {
            param([string]$Server, [string]$OutputPath, [string]$RMLInputFiles, [string]$OstressSettingsFile, [string]$OstressPath)
            Start-Ostress -TargetServer $Server -OutputFolder $OutputPath -RMLInputFiles $RMLInputFiles -OstressSettingsFile $OstressSettingsFile -OstressPath $OstressPath
        }

        [string]$functions = ""
        $fdef = ${function:Start-Ostress}
        $functions += $fdef.Ast.Extent.Text

        $functions += " "  
        $fdef = ${function:WrapProcess}
        $functions += $fdef.Ast.Extent.Text

        $export_functions = [scriptblock]::Create($functions)

        # Asyncronous
        Start-Job -ScriptBlock $sb `
            -ArgumentList @($Server.Name, "$OutputPath\$CaptureName\ostress_output", $RMLInputFiles, $OstressSettingsFile, $script:ostressPath) `
            -Name $ReplayJob `
            -InitializationScript $export_functions | Out-Null 
        # Synchronous 
        #&$sb $Server.Name "$OutputPath\$CaptureName\ostress_output" $RMLInputFiles $OstressSettingsFile 

        Invoke-WorkloadCapture `
            -ServerName $ServerName `
            -ServerOutputPath $ServerOutputPath `
            -OutputPath $OutputPath `
            -Capture $CaptureName `
            -BackupDatabases "" `
            -TraceFilters $TraceFilters `
            -ReplayJob $ReplayJob `
            -ProcessRMLFiles $false
    } # / Process
}


function Start-Ostress { 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=1)]
        [string]$TargetServer,
        [Parameter(Mandatory=$True, Position=2)]
        [string]$OutputFolder,
        [Parameter(Mandatory=$True, Position=3)]
        [string]$RMLInputFiles,
        [Parameter(Mandatory=$True, Position=4)]
        [string]$OstressSettingsFile,
        [Parameter(Mandatory=$True, Position=5)]
        [string]$OstressPath
    )  
    Process {

        Write-Verbose "Starting ostress."
        
        #Delete existing output files
        If (Test-Path $OutputFolder) { Remove-Item $OutputFolder -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item $OutputFolder -ItemType directory | Out-Null

        Copy-Item -Path $OstressSettingsFile -Destination "$($env:temp)\ostress.ini" -Force

        $ostressArgs = @(
                "-i$RMLInputFiles", 
                "-c$($env:temp)\ostress.ini", 
                "-Stcp:$TargetServer",
                "-E",
                "-o$OutputFolder", 
                "-mreplay"
            )

        #wrapProcess $OstressPath $ostressArgs
        &$OstressPath $ostressArgs
    } # / Process
}



function Invoke-WorkloadComparison {
    [CmdletBinding()]
    Param(
        # Specifies the baseline analysis name
        [Parameter(Mandatory=$True,Position=1)]
        [string]$Baseline,
        # Specifies the benchmark analysis name
        [Parameter(Mandatory=$True,Position=2)]
        [string]$Benchmark
    )
    Process {
        $arglist = @(
             "/Server",
             "(local)",
             "/Database",
             "PerfAnalysis_$Baseline",
             "/ComparisonDatabase",
             "PerfAnalysis_$Benchmark",
             "/DTAServer",
             "(local)",
             "/PressOK",
             "True"
        )
        Start-Process "$($global:RMLUtilsInstallPath)\Reporter.exe" $arglist 

        $sql = "
            WITH Baseline AS (
                SELECT 
                    TRY_PARSE(RTRIM(CD.CounterDateTime) AS datetime) AS CounterDateTime,
                    TRY_PARSE(RTRIM(D.LogStartTime) AS datetime) AS StartDate,
                    CD.CounterValue, 
                    DET.ObjectName,
                    DET.CounterName,
                    DET.InstanceName,
                    DET.DefaultScale
                FROM [PerfAnalysis_$Baseline].[dbo].[DisplayToID] AS D
                INNER JOIN [PerfAnalysis_$Baseline].[dbo].[CounterData] AS CD
                    ON D.GUID = CD.GUID
                INNER JOIN [PerfAnalysis_$Baseline].[dbo].[CounterDetails] AS DET
                    ON CD.CounterID = DET.CounterID
                WHERE D.DisplayString = 'PerfAnalysis_$Baseline'
            ),
            OffBaseline AS (
                SELECT *, 
                    offset_seconds = DATEDIFF(second,StartDate, CounterDateTime),
                    offset_minnutes = DATEDIFF(minute,StartDate, CounterDateTime)
                FROM Baseline
            ),
            Benchmark AS (
                SELECT 
                    TRY_PARSE(RTRIM(CD.CounterDateTime) AS datetime) AS CounterDateTime,
                    TRY_PARSE(RTRIM(D.LogStartTime) AS datetime) AS StartDate,
                    CD.CounterValue, 
                    DET.ObjectName,
                    DET.CounterName,
                    DET.InstanceName,
                    DET.DefaultScale
                FROM [PerfAnalysis_$Benchmark].[dbo].[DisplayToID] AS D
                INNER JOIN [PerfAnalysis_$Benchmark].[dbo].[CounterData] AS CD
                    ON D.GUID = CD.GUID
                INNER JOIN [PerfAnalysis_$Benchmark].[dbo].[CounterDetails] AS DET
                    ON CD.CounterID = DET.CounterID
                WHERE D.DisplayString = 'PerfAnalysis_$Benchmark'
            ),
            OffBechmark AS (
                SELECT *, 
                    offset_seconds = DATEDIFF(second,StartDate, CounterDateTime),
                    offset_minnutes = DATEDIFF(minute,StartDate, CounterDateTime)
                FROM Benchmark
            )
            SELECT 
                CAST(DATEADD(second,BA.offset_seconds,0) AS time) AS counter_time,
                BA.ObjectName, 
                BA.CounterName,
                BA.InstanceName,
                BA.DefaultScale,
                BA.CounterValue AS Baseline,  
                BE.CounterValue AS Benchmark
            FROM OffBaseline AS BA
            LEFT JOIN OffBechmark AS BE
                ON BA.ObjectName = BE.ObjectName
                AND BA.CounterName = BE.CounterName
                AND BA.InstanceName = BE.InstanceName
                AND BA.offset_seconds = BE.offset_seconds
            ORDER BY counter_time, ObjectName, CounterName, InstanceName
        "
    }
}


function CreateSystemDSN([string]$DSNName, [string]$ServerName, [string]$DatabaseName, [bool]$Wow64 ) {

    $Wow64String = ""
    if($Wow64) { $Wow64String = "\Wow6432Node" }

    $HKLMPath1 = "HKLM:SOFTWARE$Wow64String\ODBC\ODBC.INI\" + $DSNName
    $HKLMPath2 = "HKLM:SOFTWARE$Wow64String\ODBC\ODBC.INI\ODBC Data Sources"

    $Wow64String = ""
    if($Wow64) { $Wow64String = "\SysWOW64" }

    Get-ChildItem -Path "C:\WINDOWS$Wow64String\" -Filter "sqlncli*.dll" | Sort -Property BaseName -Descending | Select BaseName -First 1 | % { $Driver = $_.BaseName }

    $pattern = '[a-zA-Z]'
    $DriverVersion = $Driver -replace $pattern, '' 

    md $HKLMPath1 -ErrorAction silentlycontinue | Out-Null
    #set-itemproperty -path $HKLMPath1 -name Driver -value "$Driver.dll" # Native client doesn't work with relog...
    set-itemproperty -path $HKLMPath1 -name Driver -value "SQLSRV32.DLL"
    set-itemproperty -path $HKLMPath1 -name Description -value $DSNName
    set-itemproperty -path $HKLMPath1 -name Server -value $ServerName
    set-itemproperty -path $HKLMPath1 -name LastUser -value ""
    set-itemproperty -path $HKLMPath1 -name Trusted_Connection -value "Yes"
    set-itemproperty -path $HKLMPath1 -name Database -value $DatabaseName
    ## This is required to allow the ODBC connection to show up in the ODBC Administrator application.
   md $HKLMPath2 -ErrorAction silentlycontinue | Out-Null
    set-itemproperty -path $HKLMPath2 -name "$DSNName" -value "SQL Server Driver"
}


function RemoveSystemDSN([string]$DSNName, [bool]$Wow64) {

    $Wow64String = ""
    if($Wow64) { $Wow64String = "\Wow6432Node" }

    $HKLMPath1 = "HKLM:SOFTWARE$Wow64String\ODBC\ODBC.INI\" + $DSNName
    $HKLMPath2 = "HKLM:SOFTWARE$Wow64String\ODBC\ODBC.INI\ODBC Data Sources"
    if((Get-Item -Path $HKLMPath2).GetValue($DSNName) -ne $null) {
        Remove-ItemProperty -path $HKLMPath2 -name "$DSNName"
    }
    if(Test-Path $HKLMPath1) { 
        Remove-Item $HKLMPath1
    }
}
