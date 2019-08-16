[CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=1)]
        [string[]]$SourceServer,
        [Parameter(Mandatory=$true, Position=2)]
        [string]$DestinationServer,
        [Parameter(Mandatory=$false, Position=3)]
        [string]$DestinationDatabase = "diagnostic",
        [Parameter(Mandatory=$false, Position=4)]
        [string]$DestinationSchema = "dbo"
    )

    $CalculatedServerName = $SourceServer
    try {
        $installResults = Install-DbaWhoIsActive -SqlInstance $SourceServer -Database master
        $CalculatedServerName = $installResults.SqlInstance
    }
    catch {}


[int64]$snapshotId = (Get-Date -Format "yyyyMMddHHmmss")

$snapshotProp = @{
    Label = "snapshot_id"
    Expression = {$SnapshotId}
}
$serverProp = @{
    Label = "Server Name"
    Expression = {$CalculatedServerName}
}

$param = @{
    SqlInstance     = $DestinationServer
    Database        = $DestinationDatabase
    Schema          = $DestinationSchema
    AutoCreateTable = $true
    Table           = "WhoIsActive"
}

Invoke-DbaWhoIsActive -SqlInstance $SourceServer -FindBlockLeaders -GetOuterCommand -GetPlans 1 |
    Where-Object {$_ -ne $null } | 
    Select-Object $snapshotProp, $serverProp, * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors |
    Write-DbaDataTable @param 


$sql = "
IF NOT EXISTS (
	SELECT *
	FROM sys.columns
	WHERE object_id = OBJECT_ID('WhoIsActive')
		AND name = 'plan_hash'
)
ALTER TABLE [dbo].[WhoIsActive] ADD plan_hash binary(16);


UPDATE [dbo].[WhoIsActive] 
SET plan_hash = master.sys.fn_repl_hash_binary(CONVERT(varbinary(max),query_plan))
WHERE query_plan IS NOT NULL;


IF OBJECT_ID('WhoIsActive_plans') IS NULL
BEGIN
	CREATE TABLE [dbo].[WhoIsActive_plans](
		[plan_hash] [binary](16) PRIMARY KEY,
		[query_plan] [nvarchar](max) NULL
	)
END


MERGE INTO [dbo].[WhoIsActive_plans] AS trg
USING (
	SELECT DISTINCT plan_hash, query_plan
	FROM [WhoIsActive]
	WHERE query_plan IS NOT NULL
) AS src
	ON src.plan_hash = trg.plan_hash
WHEN NOT MATCHED THEN INSERT (plan_hash, query_plan)
VALUES (src.plan_hash, src.query_plan);


UPDATE [dbo].[WhoIsActive] 
SET query_plan = NULL
WHERE query_plan IS NOT NULL
	AND plan_hash IS NOT NULL;
"

Invoke-DbaQuery -SqlInstance $DestinationServer -Database $DestinationDatabase -Query $sql