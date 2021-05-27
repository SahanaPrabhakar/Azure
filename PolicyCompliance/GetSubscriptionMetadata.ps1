# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process

#Connect to Azure using the Hybrid worker system assigned managed identity
Connect-AzAccount -Identity

#Fetch management group and tenantid
$mgmtGroupName = Get-AutomationVariable -Name managementGroupName
$tenantId = Get-AutomationVariable -Name tenantId

#Fetch subscriptions
$listsubscriptions = Get-AzSubscription -TenantId $tenantId

# get database access token
$myCred = Get-AutomationPSCredential -Name 'sp_db'
$clientid= $myCred.UserName
$secret= $myCred.GetNetworkCredential().Password

$request = Invoke-RestMethod -Method POST `
           -Uri "https://login.microsoftonline.com/$tenantid/oauth2/token"`
           -Body @{ resource="https://database.windows.net/"; grant_type="client_credentials"; client_id=$clientid; client_secret=$secret }`
           -ContentType "application/x-www-form-urlencoded"
$sqldb_access_token = $request.access_token
$dbserver = 'complidashboard-sql-svr01.database.windows.net'
$dbname = 'compliance_2.0_staging_db'
$tablename = Get-AutomationVariable -Name subscriptionmetadataTable

#Empty table
$deletequery = "Delete from $tablename"
Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $deletequery


foreach($entry in $listsubscriptions)
{
    #Fetch subscription tags
    $tags = Get-AzTag -ResourceId /subscriptions/$($entry.Id)
    
    #Insert in DB   
    $query = "INSERT INTO $tablename(SubscriptionId, SubscriptionName, TenantId, State, Environment, BPID, ITSO, EHCID, AppName, ServiceLine, EIM ) values('$($entry.Id)', '$($entry.Name)', '$($entry.TenantId)','$($entry.State)', '$($tags.Properties.TagsProperty.Environment)', '$($tags.Properties.TagsProperty.BPID)', '$($tags.Properties.TagsProperty.ITSO)', '$($tags.Properties.TagsProperty.'EHC ID')', '$($tags.Properties.TagsProperty.'Application Name')', '$($tags.Properties.TagsProperty.'Service Line')', '$($tags.Properties.TagsProperty.EIM)')"
    Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $query
}     


