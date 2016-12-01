#
# Script.ps1
# 
Import-Module $PSScriptRoot\..\WorkloadUtils\WorkloadUtils.psm1

$VerbosePreference = "Continue"
#$ErrorActionPreference = "Inquire"

Invoke-WorkloadCapture -ServerName "SQLCLP01" `
    -ServerOutputPath "D:\temp\capture" `
    -OutputPath "C:\temp\results" `
    -Capture "CAPTURE" `
    -BackupDatabases "DS3" `
    -TraceFilters "exec sp_trace_setfilter @TraceID, 35, 1, 0, N'DS3'" `
    -Duration 20 `
    -Verbose


Invoke-WorkloadReplay -ServerName "SQLCLP02" `
    -RMLInputFiles "C:\temp\results\CAPTURE\ReadTrace_output\*.rml" `
    -ServerOutputPath "D:\temp\replay" `
    -OutputPath "C:\temp\results" `
    -CaptureName "REPLAY" `
    -RestoreDatabases "DS3" `
    -KeepReplication $true `
    -RestoreSourcePath "C:\temp\results\CAPTURE\Backup" `
    -TraceFilters "exec sp_trace_setfilter @TraceID, 35, 1, 0, N'DS3'" `
    -OstressSettingsFile "C:\Program Files\Microsoft Corporation\RMLUtils\sample.ini" `
    -PostRestoreScript "ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 130" `
    -Verbose

Invoke-WorkloadComparison -Baseline "CAPTURE" -Benchmark "REPLAY"
