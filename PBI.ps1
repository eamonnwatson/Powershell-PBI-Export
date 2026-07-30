#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$MasterPassword,
    [string]$StoreFile,
    [string]$ConnectionStringSecretPath = 'ConnectionStrings:AnalyticsSQL',
    [string]$ClientIdSecretPath = 'PBI:ClientID',
    [string]$ClientSecretSecretPath = 'PBI:ClientSecret',
    [string]$TenantIdSecretPath = 'PBI:TenantID',
    [ValidateSet('Trace','Debug','Information','Success','Warning','Error','Fatal')]
    [string]$LogLevel = 'Debug'
)

$ErrorActionPreference = "Stop"
$CapacityFilter = "('41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE','027965A4-D372-461A-862D-B0435B1A1FB0')"

$SqlQueries = @{
    AppUsersToRefresh = "SELECT * FROM PBI.APPS WHERE ID NOT IN (SELECT DISTINCT APPID FROM PBI.AppUsers WHERE InsertDateTime >= GETDATE() - 14)"
    ReportUsersToRefresh = "SELECT DISTINCT TOP 100 ID FROM PBI.reports WHERE WorkspaceID IN (SELECT ID FROM PBI.Folders where CapacityId IN $CapacityFilter) AND ID NOT IN (SELECT ReportID FROM PBI.ReportUsers WHERE InsertDateTime >= GETDATE() - 14)"
    GroupUsersToRefresh = "SELECT DISTINCT ID FROM PBI.Folders where CapacityId IN $CapacityFilter"
    DatasetUsersToRefresh = "SELECT DISTINCT TOP 100 ID FROM PBI.Datasets WHERE WorkspaceID IN (SELECT ID FROM PBI.Folders where CapacityId IN $CapacityFilter) AND ID NOT IN (SELECT DISTINCT DataSetID FROM PBI.DataSetUsers WHERE InsertDateTime >= GETDATE() - 14)"
    MaxActivityDate = "SELECT MAX(CAST(Creationtime AS DATE)) FROM PBI.ActivityEvents"
    ProcessPBI = "EXEC PBI.SP_PROCESSPBI"
}

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

$TableDefinitions = @{
    Groups = $GroupsTable
    Activity = $ActivityTable
    Apps = $AppsTable
    Reports = $ReportsTable
    Datasets = $DatasetTable
    Refresh = $RefreshTable
    Capacity = $CapacityTable
    AppUsers = $AppUsersTable
    ReportUsers = $ReportUsersTable
    GroupUsers = $GroupUsersTable
    DatasetUsers = $DatasetUsersTable
}

$AdminEntities = @{
    Groups = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/groups'
        Paged = $true
        TableDefinition = $TableDefinitions.Groups
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/groups'
        TargetTable = 'Folders_Staging'
        TruncateTarget = $false
        TransformName = ''
    }
    Apps = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/apps'
        Paged = $true
        TableDefinition = $TableDefinitions.Apps
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/apps'
        TargetTable = 'Apps'
        TruncateTarget = $true
        TransformName = ''
    }
    Reports = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/reports'
        Paged = $true
        TableDefinition = $TableDefinitions.Reports
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/reports'
        TargetTable = 'Reports'
        TruncateTarget = $true
        TransformName = ''
    }
    Datasets = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/datasets'
        Paged = $true
        TableDefinition = $TableDefinitions.Datasets
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/datasets'
        TargetTable = 'Datasets'
        TruncateTarget = $true
        TransformName = 'FlattenDatasetArrays'
    }
    Refresh = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables'
        Paged = $true
        TableDefinition = $TableDefinitions.Refresh
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables'
        TargetTable = 'RefreshSchedule_Staging'
        TruncateTarget = $false
        TransformName = ''
    }
    Capacity = @{
        Url = 'https://api.powerbi.com/v1.0/myorg/admin/capacities'
        Paged = $false
        TableDefinition = $TableDefinitions.Capacity
        ApiUrl = 'https://api.powerbi.com/v1.0/myorg/admin/capacities'
        TargetTable = 'Capacities'
        TruncateTarget = $true
        TransformName = ''
    }
}

$UserEntities = @{
    AppUsers = @{
        SelectQuery = $SqlQueries.AppUsersToRefresh
        ApiUrlTemplate = 'https://api.powerbi.com/v1.0/myorg/admin/apps/{0}/users'
        TableDefinition = $TableDefinitions.AppUsers
        KeyColumn = 'appid'
        DeleteTable = 'AppUsers'
        SaveTable = 'AppUsers'
        NotFoundTable = 'AppUsers'
        NotFoundIdColumn = 'AppId'
        NoUsersText = ''
        ErrorText = ''
        NoUsersInsertOnEmpty = $false
        NotFoundInsertOnError = $false
        StopOnError = $true
    }
    ReportUsers = @{
        SelectQuery = $SqlQueries.ReportUsersToRefresh
        ApiUrlTemplate = 'https://api.powerbi.com/v1.0/myorg/admin/reports/{0}/users'
        TableDefinition = $TableDefinitions.ReportUsers
        KeyColumn = 'reportid'
        DeleteTable = 'ReportUsers'
        SaveTable = 'ReportUsers'
        NotFoundTable = 'ReportUsers'
        NotFoundIdColumn = 'ReportId'
        NoUsersText = 'No Users Found'
        ErrorText = 'ReportID NOT Found'
        NoUsersInsertOnEmpty = $true
        NotFoundInsertOnError = $true
        StopOnError = $false
    }
    GroupUsers = @{
        SelectQuery = $SqlQueries.GroupUsersToRefresh
        ApiUrlTemplate = 'https://api.powerbi.com/v1.0/myorg/admin/groups/{0}/users'
        TableDefinition = $TableDefinitions.GroupUsers
        KeyColumn = 'folderid'
        DeleteTable = 'FolderUsers'
        SaveTable = 'FolderUsers'
        NotFoundTable = 'FolderUsers'
        NotFoundIdColumn = 'FolderId'
        NoUsersText = 'No Users Found'
        ErrorText = 'FolderID NOT Found'
        NoUsersInsertOnEmpty = $true
        NotFoundInsertOnError = $true
        StopOnError = $false
    }
    DatasetUsers = @{
        SelectQuery = $SqlQueries.DatasetUsersToRefresh
        ApiUrlTemplate = 'https://api.powerbi.com/v1.0/myorg/admin/datasets/{0}/users'
        TableDefinition = $TableDefinitions.DatasetUsers
        KeyColumn = 'datasetid'
        DeleteTable = 'DatasetUsers'
        SaveTable = 'DatasetUsers'
        NotFoundTable = 'DatasetUsers'
        NotFoundIdColumn = 'DatasetId'
        NoUsersText = 'No Users Found'
        ErrorText = 'DatasetID NOT Found'
        NoUsersInsertOnEmpty = $true
        NotFoundInsertOnError = $false
        StopOnError = $false
    }
}

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
    $iteration = 1
    $output = New-Object System.Collections.ArrayList

    while ($returnCount -eq 5000) {
        Write-Log "Getting data from Power BI endpoint" -Level Debug -Data @{ Url = $newURL; Iteration = $iteration; Paged = $paged }
        $data = Invoke-PowerBIRestMethod -Url $newURL -Method Get | ConvertFrom-Json
        if ($paged) {
            $newURL = $url + '?$top=5000&$skip=' + ($iteration * 5000)
            $returnCount = $data.value.Count
        }
        else {
            $returnCount = 0
        }
        Write-Log "Power BI endpoint returned records" -Level Debug -Data @{ Url = $url; Returned = $data.value.Count }
        $iteration++
        foreach ($value in $data.value) {
            [void]$output.Add($value)
        }
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

function Invoke-Sql {
    param (
        [string]$Query
    )

    Write-Log "Executing SQL query" -Level Debug -Data @{ Query = $Query }
    return Invoke-Sqlcmd -Query $Query -ConnectionString $connString
}

function Save-NotFoundRow {
    param (
        [string]$TableName,
        [string]$IdColumn,
        [string]$IdValue,
        [string]$DisplayName,
        [string]$ApiUrl
    )

    $query = "INSERT INTO PBI.$TableName ($IdColumn, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$IdValue', '$DisplayName', '$ApiUrl', GETDATE(), 'Eamonn.Watson')"
    Invoke-Sql -Query $query
}

function Transform-JsonPayload {
    param (
        [string]$Name,
        [string]$Json
    )

    if ($Name -eq 'FlattenDatasetArrays') {
        $temp = $Json | ConvertFrom-Json
        foreach ($item in $temp) {
            $item.upstreamDatasets = $item.upstreamDatasets -join ','
            $item.users = $item.users -join ','
        }
        return $temp | ConvertTo-Json
    }

    return $Json
}

function Sync-EntityUsers {
    param (
        [string]$SelectQuery,
        [string]$ApiUrlTemplate,
        [string]$TableDefinition,
        [string]$KeyColumn,
        [string]$DeleteTable,
        [string]$SaveTable,
        [string]$NotFoundTable,
        [string]$NotFoundIdColumn,
        [string]$NoUsersText,
        [string]$ErrorText,
        [switch]$NoUsersInsertOnEmpty,
        [switch]$NotFoundInsertOnError,
        [switch]$StopOnError
    )

    $items = Invoke-Sql -Query $SelectQuery
    Write-Log "Starting user entity sync" -Level Information -Data @{ EntityCount = $items.Count; SaveTable = $SaveTable }

    foreach ($row in $items) {
        Write-Log "Getting users for entity" -Level Information -Data @{ EntityId = $row.Id; SaveTable = $SaveTable }
        $apiUrl = $ApiUrlTemplate -f $row.Id

        try {
            $api = Get-PBIData -url $apiUrl -paged $false
            $entityUsers = New-Table -tableDefinition $TableDefinition -json $api -apiURL $apiUrl

            foreach ($entityRow in $entityUsers) {
                $entityRow[$KeyColumn] = $row['id']
            }

            Invoke-Sql -Query "DELETE FROM PBI.$DeleteTable WHERE $NotFoundIdColumn = '$($row.Id)'"
            SaveToDatabase -data $entityUsers -table $SaveTable
            Write-Log "Saved users for entity" -Level Information -Data @{ EntityId = $row.Id; SaveTable = $SaveTable; Rows = $entityUsers.Rows.Count }

            if ($NoUsersInsertOnEmpty -and $entityUsers.Rows.Count -eq 0) {
                Save-NotFoundRow -TableName $NotFoundTable -IdColumn $NotFoundIdColumn -IdValue $row.Id -DisplayName $NoUsersText -ApiUrl $apiUrl
                Write-Log "Inserted no-users marker row" -Level Warning -Data @{ EntityId = $row.Id; Table = $NotFoundTable }
            }
        }
        catch {
            Write-Log "Error getting users for entity" -Level Error -Data @{ EntityId = $row.Id; SaveTable = $SaveTable; Message = $_.Exception.Message }

            if ($NotFoundInsertOnError) {
                Save-NotFoundRow -TableName $NotFoundTable -IdColumn $NotFoundIdColumn -IdValue $row.Id -DisplayName $ErrorText -ApiUrl $apiUrl
                Write-Log "Inserted error marker row" -Level Warning -Data @{ EntityId = $row.Id; Table = $NotFoundTable }
            }

            if ($StopOnError) {
                Write-Log "Stopping user entity sync due to fatal entity error" -Level Fatal -Data @{ EntityId = $row.Id; SaveTable = $SaveTable }
                throw
            }
        }
    }
}

function Invoke-UserEntityLoad {
    param (
        [string]$Name
    )

    $config = $UserEntities[$Name]
    if ($null -eq $config) {
        throw "User entity '$Name' is not configured."
    }

    Sync-EntityUsers `
        -SelectQuery $config.SelectQuery `
        -ApiUrlTemplate $config.ApiUrlTemplate `
        -TableDefinition $config.TableDefinition `
        -KeyColumn $config.KeyColumn `
        -DeleteTable $config.DeleteTable `
        -SaveTable $config.SaveTable `
        -NotFoundTable $config.NotFoundTable `
        -NotFoundIdColumn $config.NotFoundIdColumn `
        -NoUsersText $config.NoUsersText `
        -ErrorText $config.ErrorText `
        -NoUsersInsertOnEmpty:([bool]$config.NoUsersInsertOnEmpty) `
        -NotFoundInsertOnError:([bool]$config.NotFoundInsertOnError) `
        -StopOnError:([bool]$config.StopOnError)
}

function Load-AdminEntity {
    param (
        [hashtable]$Config
    )

    Write-Log "Starting admin entity load" -Level Information -Data @{ Url = $Config.Url; TargetTable = $Config.TargetTable; Truncate = [bool]$Config.TruncateTarget }
    $api = Get-PBIData -url $Config.Url -paged $Config.Paged
    $api = Transform-JsonPayload -Name $Config.TransformName -Json $api
    $tableData = New-Table -tableDefinition $Config.TableDefinition -json $api -apiURL $Config.ApiUrl

    if ([bool]$Config.TruncateTarget) {
        Invoke-Sql -Query "TRUNCATE TABLE PBI.$($Config.TargetTable)"
    }

    SaveToDatabase -data $tableData -table $Config.TargetTable
    Write-Log "Completed admin entity load" -Level Information -Data @{ TargetTable = $Config.TargetTable; Rows = $tableData.Rows.Count }
}

function Invoke-AdminEntityLoad {
    param (
        [string]$Name
    )

    $config = $AdminEntities[$Name]
    if ($null -eq $config) {
        throw "Admin entity '$Name' is not configured."
    }

    Load-AdminEntity -Config $config
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
    Write-Log "Bulk copy write starting" -Level Debug -Data @{ DestinationTable = $bulkCopy.DestinationTableName; Rows = $data.Rows.Count }
    [void]$bulkCopy.WriteToServer($data)
    Write-Log "Bulk copy write completed" -Level Debug -Data @{ DestinationTable = $bulkCopy.DestinationTableName; Rows = $data.Rows.Count }
}

function Get-Activity {
    param (
        [string]$startDate,
        [string]$endDate
    )

    Write-Log "Getting activity date window" -Level Information -Data @{ StartDate = $startDate; EndDate = $endDate }
    $json = Get-PowerBIActivityEvent -StartDateTime $startDate -EndDateTime $endDate 
    $activity = New-Table -tableDefinition $ActivityTable -json $json -apiURL 'https://api.powerbi.com/v1.0/myorg/admin/activityevents'
    SaveToDatabase -data $activity -table 'ActivityEvents'
    Write-Log "Saved activity window" -Level Information -Data @{ StartDate = $startDate; EndDate = $endDate; Rows = $activity.Rows.Count }
}

function Import-File {
    param (
        [string]$path
    )

    Write-Log "Importing activity file" -Level Information -Data @{ Path = $path }
    $p = Import-Csv -Path $path
    Write-Log "Imported CSV records" -Level Debug -Data @{ Count = $p.Count }
    $activity = GetActivityTable

    foreach ($row in $p) {
        Update-Table -table $activity -json $row.AuditData
    }

    SaveToDatabase -data $activity -table 'TEMP_ActivityEvents'
    Write-Log "Saved TEMP_ActivityEvents data" -Level Information -Data @{ Rows = $activity.Rows.Count }
}

function Get-RequiredSecret {
    param (
        [string]$Path,
        [string]$DisplayName
    )

    try {
        $secret = Get-Secret -Path $Path @script:SecretStoreBoundParams
    }
    catch {
        throw "Unable to load $DisplayName from SecretStore path '$Path'. $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($secret)) {
        throw "SecretStore value for $DisplayName at path '$Path' is empty."
    }

    return $secret.Trim()
}

if (-not (Get-Module -ListAvailable -Name PSLogger)) {
    throw "PSLogger module is not installed or not available in PSModulePath."
}

Import-Module PSLogger -ErrorAction Stop

if (-not (Get-Command -Name Write-Log -ErrorAction SilentlyContinue)) {
    throw "PSLogger module does not expose Write-Log."
}

if (-not (Get-Command -Name Set-LogConfiguration -ErrorAction SilentlyContinue)) {
    throw "PSLogger module does not expose Set-LogConfiguration."
}

Set-LogConfiguration -MinimumLevel $LogLevel -Console
if (-not (Get-Module -ListAvailable -Name SecretStore)) {
    Write-Log "SecretStore module is missing" -Level Fatal
    throw "SecretStore module is not installed or not available in PSModulePath."
}

Import-Module SecretStore -ErrorAction Stop

if (-not (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
    Write-Log "SecretStore Get-Secret command is missing" -Level Fatal
    throw "SecretStore module does not expose Get-Secret."
}

if (-not (Get-Command -Name New-SecretStore -ErrorAction SilentlyContinue)) {
    Write-Log "SecretStore New-SecretStore command is missing" -Level Fatal
    throw "SecretStore module does not expose New-SecretStore."
}

if (-not (Get-Command -Name Set-Secret -ErrorAction SilentlyContinue)) {
    Write-Log "SecretStore Set-Secret command is missing" -Level Fatal
    throw "SecretStore module does not expose Set-Secret."
}

function Invoke-PbiExportRun {
    Write-Log "PBI export run started" -Level Information -Data @{ LogLevel = $LogLevel }

    $script:SecretStoreBoundParams = @{}
    $connectedToPowerBI = $false

    try {
        if (-not [string]::IsNullOrWhiteSpace($StoreFile)) {
            $script:SecretStoreBoundParams['StoreFile'] = $StoreFile
        }

        $effectiveMasterPassword = $MasterPassword
        if ([string]::IsNullOrWhiteSpace($effectiveMasterPassword)) {
            $effectiveMasterPassword = $env:SECRETSTORE_PASSWORD
        }

        if ([string]::IsNullOrWhiteSpace($effectiveMasterPassword)) {
            Write-Log "SecretStore password not provided" -Level Fatal
            throw "No SecretStore password supplied. Provide -MasterPassword or set SECRETSTORE_PASSWORD."
        }

        $script:SecretStoreBoundParams['MasterPassword'] = $effectiveMasterPassword

        $connString = Get-RequiredSecret -Path $ConnectionStringSecretPath -DisplayName 'SQL connection string'
        $clientId = Get-RequiredSecret -Path $ClientIdSecretPath -DisplayName 'Power BI client ID'
        $clientSecret = Get-RequiredSecret -Path $ClientSecretSecretPath -DisplayName 'Power BI client secret'
        $tenantID = Get-RequiredSecret -Path $TenantIdSecretPath -DisplayName 'Power BI tenant ID'
        Write-Log "Required secrets loaded from SecretStore" -Level Information

        $secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)

        Write-Log "Connecting to Power BI service account" -Level Information
        Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -Tenant $tenantID
        $connectedToPowerBI = $true

        $DS = Invoke-Sql -Query $SqlQueries.MaxActivityDate

        $LastDate = $DS[0][0]
        $CurrDate = (Get-Date).AddDays(-1).Date

        if ($LastDate -lt $CurrDate) {
            Write-Log "Activity gap detected; running backfill and full refresh block" -Level Information -Data @{ LastDate = $LastDate; CurrentDate = $CurrDate }

            foreach ($i in 1..($CurrDate - $LastDate).Days) {
                $startDate = $LastDate.AddDays($i).ToString('yyyy-MM-ddT00:00:00')
                $endDate = $LastDate.AddDays($i).ToString('yyyy-MM-ddT23:59:59')
                Get-Activity -startDate $startDate -endDate $endDate
            }

            Invoke-AdminEntityLoad -Name 'Reports'
            Invoke-AdminEntityLoad -Name 'Groups'
            Invoke-AdminEntityLoad -Name 'Apps'
            Invoke-AdminEntityLoad -Name 'Datasets'
            Invoke-AdminEntityLoad -Name 'Refresh'
            Invoke-AdminEntityLoad -Name 'Capacity'
            Invoke-UserEntityLoad -Name 'AppUsers'

        }
        else {
            Write-Log "No activity gap detected; skipping full refresh block" -Level Information -Data @{ LastDate = $LastDate; CurrentDate = $CurrDate }
        }

        Invoke-UserEntityLoad -Name 'ReportUsers'
        Invoke-UserEntityLoad -Name 'GroupUsers'
        Invoke-UserEntityLoad -Name 'DatasetUsers'

        Disconnect-PowerBIServiceAccount
        $connectedToPowerBI = $false
        Write-Log "Disconnected from Power BI service account" -Level Information

        Invoke-Sql -Query $SqlQueries.ProcessPBI
        Write-Log "Executed final processing procedure" -Level Information -Data @{ Procedure = 'PBI.SP_PROCESSPBI' }
        Write-Log "PBI export run completed" -Level Success
    }
    catch {
        Write-Log "Unhandled exception in PBI export run" -Level Fatal -Data @{ Message = $_.Exception.Message; Type = $_.Exception.GetType().FullName }
        throw
    }
    finally {
        if ($connectedToPowerBI) {
            try {
                Disconnect-PowerBIServiceAccount
                Write-Log "Disconnected from Power BI service account in finally" -Level Warning
            }
            catch {
                Write-Log "Failed to disconnect from Power BI service account in finally" -Level Error -Data @{ Message = $_.Exception.Message }
            }
        }
    }
}

Invoke-PbiExportRun
