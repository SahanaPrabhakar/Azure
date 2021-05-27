## Regularly delete records older than 90 days from reporting DB

$ServerName='complidashboard-sql-svr01.database.windows.net'
$DatabaseName='compliance_2.0_reporting_db'
$PolicystatusTable='policystatus'
$PolicystatusSummaryTable='policystatussummary'

$myCred = Get-AutomationPSCredential -Name 'db_connection_string'
$dbusername= $myCred.UserName
$dbpassword= $myCred.GetNetworkCredential().Password

Function ConnectionString([string] $ServerName, [string] $DbName)
{
    "Server=tcp:$ServerName,1433;Initial Catalog=$DBName;Persist Security Info=False;User ID=$dbusername;Password=$dbpassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

Function PurgeData($ServerName, $DatabaseName, $Table)
{
    $ConnStr = ConnectionString $ServerName $DatabaseName

    $Conn  = New-Object System.Data.SqlClient.SQLConnection($ConnStr)

    $CmdText = "DELETE FROM " + $Table + " where CollectionTimestamp < (GetDate() - 90)"
    
    $SqlCommand = New-Object system.Data.SqlClient.SqlCommand($CmdText, $Conn)

    $Conn.Open()

    [System.Data.SqlClient.SqlDataReader] $SqlReader = $SqlCommand.ExecuteReader()

    $SqlReader.close()
    $Conn.Close()
    $Conn.Dispose()    
}

#Purge records
PurgeData -ServerName $ServerName -DatabaseName $DatabaseName -Table $PolicystatusTable

PurgeData -ServerName $ServerName -DatabaseName $DatabaseName -Table $PolicystatusSummaryTable 

-----------------------------------------
SAVE PAPER - THINK BEFORE YOU PRINT!

This E-mail is confidential. 

It may also be legally privileged. If you are not the addressee you may not copy,
forward, disclose or use any part of it. If you have received this message in error,
please delete it and all copies from your system and notify the sender immediately by
return E-mail.

Internet communications cannot be guaranteed to be timely secure, error or virus-free.
The sender does not accept liability for any errors or omissions.
