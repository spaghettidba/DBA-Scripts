--
-- Queries the catalog and the schedules to identify
-- subscriptions that have failed during the last 24 hours
--
SELECT
     e.path
   , d.description
   , laststatus
   , eventtype
   , LastRunTime
FROM 
    dbo.ReportSchedule a 
    JOIN (
        SELECT * 
        FROM msdb.dbo.sysjobs b 
        WHERE TRY_CAST(name AS uniqueidentifier) IS NOT NULL
    ) AS b
    ON a.ScheduleID = b.name
    JOIN dbo.Subscriptions AS d
    ON a.SubscriptionID = d.SubscriptionID
    JOIN dbo.Catalog AS e
    ON d.report_oid = e.itemid
WHERE ( e.path LIKE '/LiftReports/%'  OR e.path LIKE '/PMReports/%' )
    AND d.[LastStatus] NOT LIKE '%was written%' --File Share subscription
    AND d.[LastStatus] NOT LIKE '%pending%' --Subscription in progress. No result yet
    AND d.[LastStatus] NOT LIKE '%mail sent%' --Mail sent successfully.
    AND d.[LastStatus] NOT LIKE '%New Subscription%' --New Sub. Not been executed yet
    AND d.[LastStatus] NOT LIKE '%been saved%' --File Share subscription
    AND d.[LastStatus] NOT LIKE '% 0 errors.' --Data Driven subscription
    AND d.[LastStatus] NOT LIKE '%succeeded%' --Success! Used in cache refreshes
    AND d.[LastStatus] NOT LIKE '%successfully saved%' --File Share subscription
    AND d.[LastStatus] NOT LIKE '%New Cache%' --New cache refresh plan
    AND d.[LastStatus] NOT LIKE '%Disabled%' --Disabled
    AND d.[LastStatus] NOT LIKE '%Disabilitata%' --Disabled
    AND d.[LastStatus] NOT LIKE '%Ready%' --Disabled
    AND d.[LastStatus] NOT LIKE '%Pronta%' --Disabled
    AND LastRunTime BETWEEN DATEADD(day,-1,GETDATE()) AND GETDATE()