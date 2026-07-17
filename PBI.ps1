#Requires -Version 5.1

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\secrets.ps1"

# Tables
$GroupsTable = "id|string,isReadOnly|boolean,isOnDedicatedCapacity|boolean,capacityId|string,capacityMigrationStatus|string,defaultDatasetStorageFormat|string,description|string,type|string,state|string,hasWorkspaceLevelSettings |boolean,name|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$ActivityTable = "id|string,RecordType|int,CreationTime|datetime,Operation|string,OrganizationId|string,UserType|int,UserKey|string,Workload|string,UserId|string,ClientIP|string,UserAgent|string,Activity|string,ItemName|string,WorkSpaceName|string,DatasetName|string,ReportName|string,CapacityId|string,CapacityName|string,WorkspaceId|string,AppName|string,ObjectId|string,DatasetId|string,ReportId|string,ArtifactId|string,ArtifactName|string,IsSuccess|boolean,ReportType|string,RequestId|string,ActivityId|string,AppReportId|string,DistributionMethod|string,ConsumptionMethod|string,AppId|string,ArtifactKind|string,RefreshEnforcementPolicy|int,ObjectType|string,ObjectDisplayName|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$AppsTable = "id|string,name|string,lastUpdate|datetime,description|string,publishedBy|string,workspaceId|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$ReportsTable = "id|string,reportType|string,name|string,webUrl|string,embedUrl|string,datasetId|string,users|string,subscriptions|string,workspaceId|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$DatasetTable = "id|string,name|string,webUrl|string,addRowsAPIEnabled|boolean,configuredBy|string,isRefreshable|boolean,isEffectiveIdentityRequired|boolean,isEffectiveIdentityRolesRequired|boolean,targetStorageMode|string,createdDate|datetime,contentProviderType|string,createReportEmbedURL|string,qnaEmbedURL|string,upstreamDatasets|string,users|string,isInPlaceSharingEnabled|string,workspaceId|string,queryScaleOutSettings|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$RefreshTable = "id|string,name|string,kind|string,startTime|datetime,endTime|datetime,refreshCount|int,refreshFailures|int,averageDuration|double,medianDuration|double,refreshesPerDay|int,lastRefresh|string,refreshSchedule|string,configuredBy|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$CapacityTable = "id|string,displayName|string,admins|string,sku|string,state|string,capacityUserAccessRight|string,region|string,users|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$AppUsersTable = "appid|string,displayName|string,emailAddress|string,appUserAccessRight|string,identifier|string,graphId|string,principalType|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$ReportUsersTable = "reportid|string,displayName|string,emailAddress|string,reportUserAccessRight|string,identifier|string,graphId|string,principalType|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$GroupUsersTable = "folderid|string,displayName|string,emailAddress|string,groupUserAccessRight|string,identifier|string,graphId|string,principalType|string,APIName|string,InsertDateTime|datetime,InsertBy|string"
$DatasetUsersTable = "datasetid|string,displayName|string,emailAddress|string,datasetUserAccessRight|string,identifier|string,graphId|string,principalType|string,APIName|string,InsertDateTime|datetime,InsertBy|string"

function Get-PBIData {
    [CmdletBinding()]
    param (
        [string]$url,
        [boolean]$paged
    )

    if ($paged) {
        $newURL = $url + '?$top=5000'
    }
        else {
        $newURL = $url
    }

    $returnCount = 5000    
    $interation = 1
    $output = @()

    while ($returnCount -eq 5000) {
        Write-Host "Getting data from $newURL"
        $data = Invoke-PowerBIRestMethod -Url $newURL -Method Get | ConvertFrom-Json
        if ($paged) {
            $newURL = $url + '?$top=5000&$skip=' + ($interation * 5000) 
            $returnCount = $data.value.Count
        }
        else {
            $returnCount = 0
        }
        Write-Host "Returned $($data.value.Count) records"
        $interation++
        $output += $data.value
    }

    return $output | ConvertTo-Json
}

function New-Table {
    [OutputType([System.Data.DataTable])]
    [CmdletBinding()]
    param (
        [string]$tableDefinition,
        [string]$json,
        [string]$apiURL
    )

    $table = GetTable -table $tableDefinition

    $data = $json | ConvertFrom-Json 

    foreach ($row in $data) {
        $newRow = $table.NewRow()
        foreach ($column in $table.Columns) {
            if ($null -eq $row.$($column.ColumnName)) {
                $columnValue = [DBNull]::Value
            }
            elseif ($row.$($column.ColumnName) -is [Array]) {
                $columnValue = $row.$($column.ColumnName) -join ','
            }
            else {
                $columnValue = $row.$($column.ColumnName)
            }
            $newRow[$column.ColumnName] = $columnValue
        }

        $newRow["InsertBy"] = 'PBI.PS1'
        $newRow["InsertDateTime"] = [datetime](Get-Date)
        $newRow["APIName"] = $apiURL

        [void]$table.Rows.Add($newRow)
    }

    return ,$table
}

function Get-AppUsers {

    $apps = Invoke-Sqlcmd -Query "SELECT * FROM PBI.APPS WHERE ID NOT IN (SELECT DISTINCT APPID FROM PBI.AppUsers WHERE InsertDateTime >= GETDATE() - 14)" -ConnectionString $connString

    foreach ($row in $apps){
        Write-Host "Getting users for $($row.Id)"
        $api = Get-PBIData -url "https://api.powerbi.com/v1.0/myorg/admin/apps/$($row.Id)/users" -paged $false
        $appUsers = New-Table -tableDefinition $AppUsersTable -json $api -apiURL "https://api.powerbi.com/v1.0/myorg/admin/apps/$($row.Id)/users"
        
        foreach ($appRow in $appUsers) {
            $appRow["appid"] = $row["id"]
        }

        Invoke-Sqlcmd -Query "DELETE FROM PBI.AppUsers WHERE AppId = '$($row.Id)'" -ConnectionString $connString
        SaveToDatabase -data $appUsers -table 'AppUsers'
    }

}

function Get-ReportUsers {

    $reports = Invoke-Sqlcmd -Query "SELECT DISTINCT TOP 100 ID FROM PBI.reports WHERE WorkspaceID IN (SELECT ID FROM PBI.Folders where CapacityId IN ('41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE','027965A4-D372-461A-862D-B0435B1A1FB0')) AND ID NOT IN (SELECT ReportID FROM PBI.ReportUsers WHERE InsertDateTime >= GETDATE() - 14)" -ConnectionString $connString

    foreach ($row in $reports){
        Write-Host "Getting users for $($row.Id)"
        
        try {
            $api = Get-PBIData -url "https://api.powerbi.com/v1.0/myorg/admin/reports/$($row.Id)/users" -paged $false
            $reportUsers = New-Table -tableDefinition $ReportUsersTable -json $api -apiURL "https://api.powerbi.com/v1.0/myorg/admin/reports/$($row.Id)/users"
            
            foreach ($appRow in $reportUsers) {
                $appRow["reportid"] = $row["id"]
            }
    
            Invoke-Sqlcmd -Query "DELETE FROM PBI.ReportUsers WHERE ReportId = '$($row.Id)'" -ConnectionString $connString
            SaveToDatabase -data $reportUsers -table 'ReportUsers'
    
            if ($reportUsers.Rows.Count -eq 0) {
                Invoke-Sqlcmd -Query "INSERT INTO PBI.ReportUsers (ReportID, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$($row.Id)', 'No Users Found', 'https://api.powerbi.com/v1.0/myorg/admin/reports/$($row.Id)/users', GETDATE(), 'Eamonn.Watson')" -ConnectionString $connString
            }
        }
        catch {
            Write-Host "Error getting users for $($row.Id)"            
            Write-Host $_.Exception.Message
            Invoke-Sqlcmd -Query "INSERT INTO PBI.ReportUsers (ReportID, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$($row.Id)', 'ReportID NOT Found', 'https://api.powerbi.com/v1.0/myorg/admin/reports/$($row.Id)/users', GETDATE(), 'Eamonn.Watson')" -ConnectionString $connString
        }
        
    }

}

function Get-GroupUsers {

    $groups = Invoke-Sqlcmd -Query "SELECT DISTINCT ID FROM PBI.Folders where CapacityId IN ('41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE','027965A4-D372-461A-862D-B0435B1A1FB0')" -ConnectionString $connString
    
    foreach ($row in $groups){
        Write-Host "Getting users for $($row.Id)"
        
        try {
            $api = Get-PBIData -url "https://api.powerbi.com/v1.0/myorg/admin/groups/$($row.Id)/users" -paged $false
            $groupUsers = New-Table -tableDefinition $GroupUsersTable -json $api -apiURL "https://api.powerbi.com/v1.0/myorg/admin/groups/$($row.Id)/users"
            
            foreach ($appRow in $groupUsers) {
                $appRow["folderid"] = $row["id"]
            }
    
            Invoke-Sqlcmd -Query "DELETE FROM PBI.FolderUsers WHERE FolderId = '$($row.Id)'" -ConnectionString $connString
            SaveToDatabase -data $groupUsers -table 'FolderUsers'

            if ($groupUsers.Rows.Count -eq 0) {
                Invoke-Sqlcmd -Query "INSERT INTO PBI.FolderUsers (FolderID, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$($row.Id)', 'No Users Found', 'https://api.powerbi.com/v1.0/myorg/admin/groups/$($row.Id)/users', GETDATE(), 'Eamonn.Watson')" -ConnectionString $connString
            }
        }
        catch {
            Write-Host "Error getting users for $($row.Id)"
            Write-Host $_.Exception.Message
            Invoke-Sqlcmd -Query "INSERT INTO PBI.FolderUsers (FolderID, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$($row.Id)', 'FolderID NOT Found', 'https://api.powerbi.com/v1.0/myorg/admin/groups/$($row.Id)/users', GETDATE(), 'Eamonn.Watson')" -ConnectionString $connString
        }
    }

}

function Get-DatasetUsers {

    $datasets = Invoke-Sqlcmd -Query "SELECT DISTINCT TOP 100 ID FROM PBI.Datasets WHERE WorkspaceID IN (SELECT ID FROM PBI.Folders where CapacityId IN ('41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE','027965A4-D372-461A-862D-B0435B1A1FB0')) AND ID NOT IN (SELECT DISTINCT DataSetID FROM PBI.DataSetUsers WHERE InsertDateTime >= GETDATE() - 14)" -ConnectionString $connString

    foreach ($row in $datasets){
        Write-Host "Getting users for $($row.Id)"
        
        try {
            $api = Get-PBIData -url "https://api.powerbi.com/v1.0/myorg/admin/datasets/$($row.Id)/users" -paged $false
            $dsUsers = New-Table -tableDefinition $DatasetUsersTable -json $api -apiURL "https://api.powerbi.com/v1.0/myorg/admin/datasets/$($row.Id)/users"
            
            foreach ($appRow in $dsUsers) {
                $appRow["datasetid"] = $row["id"]
            }
    
            Invoke-Sqlcmd -Query "DELETE FROM PBI.DatasetUsers WHERE DatasetId = '$($row.Id)'" -ConnectionString $connString
            SaveToDatabase -data $dsUsers -table 'DatasetUsers'    

            if ($dsUsers.Rows.Count -eq 0) {
                Invoke-Sqlcmd -Query "INSERT INTO PBI.DatasetUsers (DatasetId, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$($row.Id)', 'No Users Found', 'https://api.powerbi.com/v1.0/myorg/admin/datasets/$($row.Id)/users', GETDATE(), 'Eamonn.Watson')" -ConnectionString $connString
            }
        }
        catch {
            Write-Host "Error getting users for $($row.Id)"
            Write-Host $_.Exception.Message
        }
    }

}

function GetTable {
    param (
        [string]$table
    )

    $dataTable = New-Object System.Data.DataTable
    $columns = $table -split ','

    ForEach ($column in $columns) {
        $column = $column -split '\|'
        [void]$dataTable.Columns.Add($column[0], $column[1])
    }

    return ,$dataTable
}

function SaveToDatabase {
    param (
        [System.Data.DataTable]$data,
        [string]$table
    )

    $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($connString)
    $bulkCopy.DestinationTableName = "PBI.$table"
    $bulkCopy.BulkCopyTimeout = 900
    [void]$bulkCopy.WriteToServer($data)
}

function Get-Groups {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/groups' -paged $true
    $groups = New-Table -tableDefinition $GroupsTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/groups' 
    SaveToDatabase -data $groups -table 'Folders_Staging'
}

function Get-Activity {
    param (
        [string]$startDate,
        [string]$endDate
    )

    Write-Host "Getting activity from $startDate to $endDate"
    $json = Get-PowerBIActivityEvent -StartDateTime $startDate -EndDateTime $endDate 
    $activity = New-Table -tableDefinition $ActivityTable -json $json -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/activityevents'
    SaveToDatabase -data $activity -table 'ActivityEvents'
}

function Get-Apps {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/apps' -paged $true
    $apps = New-Table -tableDefinition $AppsTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/apps'
    Invoke-Sqlcmd -Query "TRUNCATE TABLE PBI.Apps" -ConnectionString $connString
    SaveToDatabase -data $apps -table 'Apps'
}

function Get-Reports {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/reports' -paged $true
    $reports = New-Table -tableDefinition $ReportsTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/reports'
    Invoke-Sqlcmd -Query "TRUNCATE TABLE PBI.Reports" -ConnectionString $connString
    SaveToDatabase -data $reports -table 'Reports'
}

function Get-Datasets {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/datasets' -paged $true
     

    $temp = $api | ConvertFrom-Json

    foreach ($item in $temp) {
        $item.upstreamDatasets = $item.upstreamDatasets -join ','
        $item.users = $item.users -join ','
    }

    $api = $temp | ConvertTo-Json
    $datasets = New-Table -tableDefinition $DatasetTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/datasets'
    Invoke-Sqlcmd -Query "TRUNCATE TABLE PBI.Datasets" -ConnectionString $connString
    SaveToDatabase -data $datasets -table 'Datasets'
}

function Get-Refresh {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables' -paged $true
    $refresh = New-Table -tableDefinition $RefreshTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables'
    SaveToDatabase -data $refresh -table 'RefreshSchedule_Staging'
}

function Get-Capacity {
    $api = Get-PBIData -url 'https://api.powerbi.com/v1.0/myorg/admin/capacities' -paged $false
    $capacities = New-Table -tableDefinition $CapacityTable -json $api -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/capacities'
    Invoke-Sqlcmd -Query "TRUNCATE TABLE PBI.Capacities" -ConnectionString $connString
    SaveToDatabase -data $capacities -table 'Capacities'
}

function Import-File {
    param (
        [string]$path
    )

    Write-Host "Importing $path"
    $p = Import-Csv -Path $path
    Write-Host "Returned records"
    $activity = GetActivityTable

    foreach ($row in $p) {
        Update-Table -table $activity -json $row.AuditData
    }

    SaveToDatabase -data $activity -table 'TEMP_ActivityEvents'
}

# Credentials loaded from secrets.ps1

$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)

try {
	Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -Tenant $tenantID
} catch {
 $_ | Format-List * -Force

    $_.Exception
    $_.Exception.InnerException
   exit
}

$DS = Invoke-Sqlcmd -Query "SELECT MAX(CAST(Creationtime AS DATE)) FROM PBI.ActivityEvents" -ConnectionString $connString

$LastDate = $DS[0][0]
$CurrDate = (Get-Date).AddDays(-1).Date

if ($LastDate -lt $CurrDate) {

    foreach ($i in 1..($CurrDate - $LastDate).Days) {
        $startDate = $LastDate.AddDays($i).ToString('yyyy-MM-ddT00:00:00')
        $endDate = $LastDate.AddDays($i).ToString('yyyy-MM-ddT23:59:59')
        Get-Activity -startDate $startDate -endDate $endDate
    }    
    
    Get-Reports
    Get-Groups
    Get-Apps
    Get-Datasets
    Get-Refresh
    Get-Capacity
    Get-AppUsers

} 

Get-ReportUsers
Get-GroupUsers
Get-DataSetUsers

Disconnect-PowerBIServiceAccount

Invoke-Sqlcmd -Query "EXEC PBI.SP_PROCESSPBI" -ConnectionString $connString
