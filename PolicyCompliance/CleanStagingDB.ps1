## Delete records which have been copied to reporting DB

$Server = 'complidashboard-sql-svr01.database.windows.net'
$Database='compliance_2.0_staging_db'
#Make this an array and input all tables here
$PolicystatusTable='policystatus_tenant_hsbc'
$PolicystatusSummaryTable='policystatussummary_hsbc'

$myCred = Get-AutomationPSCredential -Name 'db_connection_string'
$dbusername= $myCred.UserName
$dbpassword= $myCred.GetNetworkCredential().Password

Function ConnectionString([string] $ServerName, [string] $DbName)
{
    "Server=tcp:$ServerName,1433;Initial Catalog=$DBName;Persist Security Info=False;User ID=$dbusername;Password=$dbpassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

#Delete record 
Function CleanDB($ServerName, $DBName, $TableName)
{
    try {
    
        $ConnStr = ConnectionString $ServerName $DBName
        $DelQuery = "DELETE FROM " + $TableName + " where isDelete='true'"

        Invoke-SqlCmd -Query $DelQuery -ConnectionString $ConnStr 
    }
    Catch [System.Exception]
    {

        $ex = $_.Exception
        Write-Host $ex.Message
    }
}

# Later : Iterate through all staging tables for different tenants

CleanDB -ServerName $Server -DBName $Database -TableName $PolicystatusTable

CleanDB -ServerName $Server -DBName $Database -TableName $PolicystatusSummaryTable 

