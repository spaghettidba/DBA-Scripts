#set policy online for san disks
"san policy=OnlineAll" | Out-File $Env:Temp\sanpol.txt -Encoding ascii
diskpart /s $Env:Temp\sanpol.txt


# bring disks online
get-disk | Set-disk -IsOffline $false
get-disk | Where-Object { $_.PartitionStyle -eq "RAW" } | ForEach-Object {

    Initialize-Disk -Number $_.Number -PartitionStyle GPT
    new-partition -disknumber $_.Number -usemaximumsize | format-volume -filesystem NTFS -AllocationUnitSize 65536

}

# Assign drive letters based on size
$drives = "T", "L", "D"

$sortedDisks = get-partition | Where-Object { $_.Type -eq "Basic" -and $_.DriveLetter.tostring().trim() -eq ""} | Sort-Object -Property Size

for($i = 0; $i -lt $sortedDisks.Count; $i++) {

    $currentDisk = $sortedDisks[$i]
    $currentDisk | Set-Partition -NewDriveLetter $drives[$i]

}


#Disable Recycle bin
$volumes=Get-Volume | Where-Object {$_.FileSystem -eq "NTFS" -and $_.DriveLetter -ne "C"}
$Drives=foreach ($volume in $volumes) {
    $DriveLetter=$Volume.DriveLetter
    [string]$ObjectId=($Volume.ObjectId | Select-String -Pattern "Volume{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}\\").Matches.Value.SubString(6,38)
    Remove-Item -Path $('{0}:\$Recycle.Bin' -f $DriveLetter) -Force -Recurse -ErrorAction SilentlyContinue
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$ObjectId" -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$ObjectId" -Name NukeOnDelete -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$ObjectId" -Name MaxCapacity -Type DWord -Value 0
}

#Remove Everyone permissions
icacls D:\ /remove:g "everyone"
icacls L:\ /remove:g "everyone"
icacls T:\ /remove:g "everyone"


#create path for tempdb
mkdir "T:\MSSQL15.MSSQLSERVER\MSSQL\Data"
