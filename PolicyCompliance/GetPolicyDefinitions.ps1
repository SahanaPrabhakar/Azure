# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process

#Connect to Azure using the Hybrid worker system assigned managed identity
Connect-AzAccount -Identity

#Fetch management group and tenantid
$mgmtGroupName = Get-AutomationVariable -Name managementGroupName
$tenantId = Get-AutomationVariable -Name tenantId

#Fetch policy definitions
$policyDefinitions = Get-AzPolicyDefinition -ManagementGroupName $mgmtGroupName -Custom -ErrorAction Stop

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
$tablename = Get-AutomationVariable -Name policyDefinitionTable

#Empty table
$deletequery = "Delete from $tablename"
Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $deletequery

foreach($entry in $policyDefinitions)
{ 
    $excudeFromAlerts = $entry.Properties.Metadata.'exclude-from-alerts'
    $excludeFromReporting = $entry.Properties.Metadata.'exclude-reporting'
        
    #Insert in DB
    $query = "INSERT INTO $tablename(Name, ResourceId, ResourceName, PolicyType, ExcludeFromAlerts, ExcludeFromReporting, Priority, Source, TenantId, PolicyDefinitionId) values('$($entry.name)', '$($entry.ResourceId)', '$($entry.ResourceName)', '$($entry.Properties.PolicyType)', '$excludeFromAlerts', '$excludeFromReporting', '$($entry.Properties.Metadata.priority)', '$($entry.Properties.Metadata.source)', '$tenantId', '$($entry.PolicyDefinitionId)')"

    Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $query -ErrorAction SilentlyContinue
}     

