#requires -version 2.0

$SrcServer = 'complidashboard-sql-svr01.database.windows.net'
$SrcDatabase='compliance_2.0_staging_db'

$DestServer='complidashboard-sql-svr01.database.windows.net'
$DestDatabase='compliance_2.0_reporting_db'
$DestPolicyDefTable='policydefinitions'
$DestSubscriptionTable='subscriptionmetadata'
$DestPolicystatusTable='policystatus'
$DestPolicystatusSummaryTable='policystatussummary'
$Truncate='False'

# SAME CREDENTIALS ARE USED FOR STAGING AND REPORTING DB #
$myCred = Get-AutomationPSCredential -Name 'db_connection_string'
$dbusername= $myCred.UserName
$dbpassword= $myCred.GetNetworkCredential().Password

$tenantNames = @(Get-AutomationVariable -Name tenantNames -ErrorAction Stop)

Function ConnectionString([string] $ServerName, [string] $DbName)
{
    "Server=tcp:$ServerName,1433;Initial Catalog=$DBName;Persist Security Info=False;User ID=$dbusername;Password=$dbpassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}


############## COPY DATA FROM STAGING DB TO LOG ANALYTICS ##################
$PolicyDefTableLAWS = 'policyDefinitions_alltenants'
$SubscriptionTableLAWS='subscriptionmetadata_alltenants'
$PolicystatusTableLAWS='policystatus_alltenants'
$PolicystatusSummaryTableLAWS='policystatussummary_alltenants'

# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing -ErrorAction Stop
    return $response.StatusCode
}

Function CopyFromStagingDBToLAWS($DBTableName,$LATableName)
{
    #Fetch data from staging DB

    $ConnStr = ConnectionString $SrcServer $SrcDatabase

    if(($LATableName -eq $PolicystatusTableLAWS) -or ($LATableName -eq $PolicystatusSummaryTableLAWS) )
    {
        $query = "select * from " + $DBTableName + " where isDelete='false'"
    } else {
        $query = "select * from " + $DBTableName
    }
        
    $output = Invoke-SqlCmd -Query $query -ConnectionString $ConnStr
    
    # SWITCH TO MANAGED IDENTITY
    ### Obtain the Access Token to write the out to LA
    # Fetch from Automation Account Credential store
    $myCred = Get-AutomationPSCredential -Name 'laws_sp'
    $clientid= $myCred.UserName
    $secret= $myCred.GetNetworkCredential().Password
    $securePassword = ConvertTo-SecureString $secret -AsPlainText -Force

    $tenantId='e0fd434d-ba64-497b-90d2-859c472e1a92'
    $pscredential = New-Object -TypeName System.Management.Automation.PSCredential($clientid, $securePassword)
    Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId

    $resourceGroupName = 'hsbc-multi-compliance-nonprod-01-rg-compliance2.0-poc'
    $workspaceName = 'hsbc-multi-compliance-nonprod-01-euw-HybridLA-01'

    # Ignore irrelevant warning on deprecation of Get-AzOperationalInsightsWorkspaceSharedKeys alias. Using the right one below.
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    $sharedKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $resourceGroupName -Name $workspaceName).PrimarySharedKey 
    $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceName).CustomerId

    # Specify the name of the record type that you'll be creating
    $LogType = $LATableName

    # You can use an optional field to specify the timestamp from the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
    $TimeStampField = ""

    # Submit the data to the API endpoint
    # Batch the payloads
    for($i=0; $i -lt $output.count; $i += 1000)
    {
        $payload = $output[$i..($i+999)]
        $json = $payload | ConvertTo-Json
        Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $LogType            
    }
}

<#foreach($entry in $tenantNames)
{#>
    $entry='hsbc'
    $PolDefTable = 'policydefinitions_hsbc'
    $SubscriptionTable = 'subscriptionmetadata_hsbc'
    $PolicystatusTable = 'policystatus_hsbc'
    $PolicystatusSummaryTable = 'policystatussummary_hsbc'
    
    CopyFromStagingDBToLAWS -DBTableName $PolDefTable -LATableName $PolicyDefTableLAWS

    CopyFromStagingDBToLAWS -DBTableName $SubscriptionTable -LATableName $SubscriptionTableLAWS

    CopyFromStagingDBToLAWS -DBTableName $PolicystatusTable -LATableName $PolicystatusTableLAWS

    CopyFromStagingDBToLAWS -DBTableName $PolicystatusSummaryTable -LATableName $PolicystatusSummaryTableLAWS
#}



##################################################################################################
#Copy data to reporting database and MARK SOURCE POLICYSTATUS AND POLICYSTATUSSUMMARY FOR DELETION
##################################################################################################

## FUNCTION USED FOR POLICYSTATUS AND POLICYSTATUSSUMMARY ##
Function CopyPolicyStatusTableData($SrcS, $SrcD, $SrcT, $DestS, $DestD, $DestT)
{
    $SrcConnStr = ConnectionString $SrcS $SrcD

    $SrcConn  = New-Object System.Data.SqlClient.SQLConnection($SrcConnStr)

    $CmdText = "SELECT * FROM " + $SrcT + " where isDelete='false'"
   
    $SqlCommand = New-Object system.Data.SqlClient.SqlCommand($CmdText, $SrcConn)

    $SrcConn.Open()

    [System.Data.SqlClient.SqlDataReader] $SqlReader = $SqlCommand.ExecuteReader()

    Try
    {
        $DestConnStr = ConnectionString $DestS $DestD

        # delete dest before copy if Truncate is true
        $DestConn  = New-Object System.Data.SqlClient.SQLConnection($DestConnStr)
           
        $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($DestConnStr, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
        $bulkCopy.DestinationTableName = $DestT
        $bulkCopy.BatchSize = 10000
        $bulkCopy.BulkCopyTimeout = 120
        $bulkCopy.WriteToServer($SqlReader)

        # Mark source table for deletion
        $UpdateQuery = "Update " + $SrcT + " set isDelete='true'"

        Invoke-SqlCmd -Query $UpdateQuery -ConnectionString $SrcConnStr
        
    }
    Catch [System.Exception]
    {

        $ex = $_.Exception
        Write-Host $ex.Message
    }

    Finally
    {
        Write-Host “Table $SrcT in $SrcD database on $SrcS has been copied to table $DestT in $DestD database on $DestS”
        
        $SqlReader.close()
        $SrcConn.Close()
        $SrcConn.Dispose()
        $bulkCopy.Close()
    }
}

##FUNCTION USED FOR POLICYDEFINITIONS AND SUBSCRIPTIONMETADATA##
Function CopyTableData($SrcS, $SrcD, $SrcT, $DestS, $DestD, $DestT)
{

    $SrcConnStr = ConnectionString $SrcS $SrcD

    $SrcConn  = New-Object System.Data.SqlClient.SQLConnection($SrcConnStr)

    $CmdText = "SELECT * FROM " + $SrcT
   
    $SqlCommand = New-Object system.Data.SqlClient.SqlCommand($CmdText, $SrcConn)

    $SrcConn.Open()

    [System.Data.SqlClient.SqlDataReader] $SqlReader = $SqlCommand.ExecuteReader()

    Try
    {
        $DestConnStr = ConnectionString $DestS $DestD

        # delete dest before copy
        $DelQuery = "DELETE FROM " + $DestT + " where tenantId='" + $tenantId +"'"

        Invoke-SqlCmd -Query $DelQuery -ConnectionString $DestConnStr            
        
        $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($DestConnStr, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
        $bulkCopy.DestinationTableName = $DestT
        $bulkCopy.BatchSize = 10000
        $bulkCopy.BulkCopyTimeout = 120
        $bulkCopy.WriteToServer($SqlReader)     
    }
    Catch [System.Exception]
    {

        $ex = $_.Exception
        Write-Host $ex.Message
    }

    Finally
    {
        Write-Host “Table $SrcT in $SrcD database on $SrcS has been copied to table $DestT in $DestD database on $DestS”
        
        $SqlReader.close()
        $SrcConn.Close()
        $SrcConn.Dispose()
        $bulkCopy.Close()
    }
}
<#foreach($entry in $tenantNames)
{#>
    $entry='hsbc'
    $PolDefTable = 'policydefinitions_'+$entry
    $SubscriptionTable = 'subscriptionmetadata_' + $entry
    $PolicystatusTable = 'policystatus_' + $entry
    $PolicystatusSummaryTable = 'policystatussummary_' + $entry
       
    #Copy policydefinitions
    CopyTableData -SrcS $SrcServer -SrcD $SrcDatabase -SrcT $PolDefTable -DestS $DestServer -DestD $DestDatabase -DestT $DestPolicyDefTable -ErrorAction Stop

    #Copy subscription metadata
    CopyTableData -SrcS $SrcServer -SrcD $SrcDatabase -SrcT $SubscriptionTable -DestS $DestServer -DestD $DestDatabase -DestT $DestSubscriptionTable

    #Copy policystatus
    CopyPolicyStatusTableData -SrcS $SrcServer -SrcD $SrcDatabase -SrcT $PolicystatusTable -DestS $DestServer -DestD $DestDatabase -DestT $DestPolicystatusTable 

    #Copy policystatus summary
    CopyPolicyStatusTableData -SrcS $SrcServer -SrcD $SrcDatabase -SrcT $PolicystatusSummaryTable -DestS $DestServer -DestD $DestDatabase -DestT $DestPolicystatusSummaryTable




