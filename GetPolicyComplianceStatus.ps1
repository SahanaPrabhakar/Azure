# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process

#Connect to Azure using the Hybrid worker system assigned managed identity
Connect-AzAccount -Identity

#Fetch management group and tenantid
$mgmtGroupName = Get-AutomationVariable -Name managementGroupName -ErrorAction Stop
$tenantId = Get-AutomationVariable -Name tenantId -ErrorAction Stop

# Get an access token for managed identities for Azure resources
$response = Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' `
                              -Headers @{Metadata="true"} -ErrorAction Stop
$content =$response.Content | ConvertFrom-Json -ErrorAction Stop
$mi_access_token = $content.access_token

$authHeader = @{
  'Authorization'='Bearer ' + $mi_access_token
}

# Create a splatting variable for Invoke-RestMethod
$invokeRest = @{
  Uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/'+ $mgmtGroupName +'/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01'
  Method = 'POST'
  ContentType = 'application/json'
  Headers = $authHeader
}

# Invoke the PolicyStatus REST API
$response = Invoke-RestMethod @invokeRest -ErrorAction Stop

$policyStatus = [pscustomobject]$response.value

while($response.'@odata.nextLink' -ne $null){
      $invokeRest = @{
      Uri = $response.'@odata.nextLink'
      Method = 'POST'
      ContentType = 'application/json'
      Headers = $authHeader
    }

    $response = Invoke-RestMethod @invokeRest -ErrorAction Stop

    $policyStatus += $response.value
}

# Fetch PolicyStatus Summary
$policyStatusSummary = Get-AzPolicyStateSummary -ManagementGroupName $mgmtGroupName -ErrorAction Stop

$collectionTime = Get-Date -ErrorAction Stop

### Obtain the Access Token to write the output to SQL DB
# Fetch from Automation Account Credential store
$myCred = Get-AutomationPSCredential -Name 'sp_db' -ErrorAction Stop
$clientid= $myCred.UserName
$secret = $myCred.GetNetworkCredential().Password

$request = Invoke-RestMethod -Method POST `
           -Uri "https://login.microsoftonline.com/$tenantid/oauth2/token"`
           -Body @{ resource="https://database.windows.net/"; grant_type="client_credentials"; client_id=$clientid; client_secret=$secret }`
           -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
$sqldb_access_token = $request.access_token
$dbserver = 'complidashboard-sql-svr01.database.windows.net'
$dbname = 'compliance_2.0_staging_db'
$policystatusTablename = Get-AutomationVariable -Name policyStatusTable
$policystatusSummaryTablename = Get-AutomationVariable -Name policystatusSummaryTable

foreach($entry in $policyStatus)
{    
    [datetime]$timeofoccurance = $entry.Timestamp    
    $query = "INSERT INTO $policystatusTablename(CollectionTimestamp, Timestamp,SubscriptionId,ManagementGroupIds,ResourceType,ResourceId,IsCompliant,ComplianceState, PolicyAssignmentName,PolicyAssignmentId,PolicyDefinitionName,PolicyDefinitionId,PolicySetDefinitionId, PolicySetDefinitionName, TenantId) values('$collectionTime','$timeofoccurance', '$($entry.SubscriptionId)', '$($entry.ManagementGroupIds)', '$($entry.ResourceType)', '$($entry.ResourceId)', '$($entry.IsCompliant)','$($entry.ComplianceState)', '$($entry.PolicyAssignmentName)', '$($entry.PolicyAssignmentId)', '$($entry.PolicyDefinitionName)', '$($entry.PolicyDefinitionId)', '$($entry.PolicySetDefinitionId)', '$($entry.PolicySetDefinitionName)', '$tenantid')"
    
    Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $query -ErrorAction Stop
}     

foreach($entry in $policyStatusSummary)
{    
    $query = "INSERT INTO $policystatusSummaryTablename(CollectionTimestamp, NonCompliantResources, NonCompliantPolicies, ManagementGroupName, TenantId) values('$collectionTime','$($entry.Results.NonCompliantResources)', '$($entry.Results.NonCompliantPolicies)', '$mgmtGroupName', '$tenantId') "
    Invoke-SqlCmd -ServerInstance $dbserver -Database $dbname -AccessToken $sqldb_access_token -Query $query -ErrorAction Stop
}


