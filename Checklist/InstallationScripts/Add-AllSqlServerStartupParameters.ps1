$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $script_path

# many trace flags have become obsolete
# check your SQL Server version

# .\Add-SqlServerStartupParameter.ps1 "-T1117"
# .\Add-SqlServerStartupParameter.ps1 "-T1118"
# .\Add-SqlServerStartupParameter.ps1 "-T2371"
# .\Add-SqlServerStartupParameter.ps1 "-T2389"
# .\Add-SqlServerStartupParameter.ps1 "-T2390"
# .\Add-SqlServerStartupParameter.ps1 "-T4199"

.\Add-SqlServerStartupParameter.ps1 "-T3226"
