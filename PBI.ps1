#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [Alias('f')]
    [ValidateNotNullOrEmpty()]
    [string]$SecretFile,

    [Parameter(Mandatory = $false)]
    [Alias('p')]
    [ValidateNotNullOrEmpty()]
    [System.Security.SecureString]$MasterPassword,
 
    [Parameter(Mandatory = $false)]
    [Alias('d')]
    [switch]$DryRun,

    [Parameter(Mandatory = $true)]
    [Alias('c')]
    [ValidateNotNullOrEmpty()]
    [string]$ConnectionStringName,

    [ValidateSet('Trace','Debug','Information','Success','Warning','Error','Fatal')]
    [string]$LogLevel = 'Information'
)

$ErrorActionPreference = "Stop"
$CapacityFilter = "('41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE','027965A4-D372-461A-862D-B0435B1A1FB0')"

$SqlQueries = @{
    AppUsersToRefresh = "SELECT DISTINCT ID FROM REPORTINGSERVICES.PBI.APPS WHERE ID NOT IN (SELECT DISTINCT APPID FROM REPORTINGSERVICES.PBI.AppUsers WHERE InsertDateTime >= GETDATE() - 14)"
    ReportUsersToRefresh = "SELECT DISTINCT TOP 50 ID FROM REPORTINGSERVICES.PBI.reports WHERE WorkspaceID IN (SELECT ID FROM REPORTINGSERVICES.PBI.Folders where CapacityId IN $CapacityFilter) AND ID NOT IN (SELECT ReportID FROM REPORTINGSERVICES.PBI.ReportUsers WHERE InsertDateTime >= GETDATE() - 14)"
    GroupUsersToRefresh = "SELECT DISTINCT TOP 50 ID FROM REPORTINGSERVICES.PBI.Folders WHERE IsCurrent = 1 AND CapacityId IN $CapacityFilter AND InsertDateTime >= GETDATE() - 14"
    DatasetUsersToRefresh = "SELECT DISTINCT TOP 50 ID FROM REPORTINGSERVICES.PBI.Datasets WHERE WorkspaceID IN (SELECT ID FROM REPORTINGSERVICES.PBI.Folders where CapacityId IN $CapacityFilter) AND ID NOT IN (SELECT DISTINCT DataSetID FROM REPORTINGSERVICES.PBI.DataSetUsers WHERE InsertDateTime >= GETDATE() - 14)"
    MaxActivityDate = "SELECT MAX(CAST(Creationtime AS DATE)) FROM REPORTINGSERVICES.PBI.ActivityEvents"
    ProcessPBI = "EXEC REPORTINGSERVICES.PBI.SP_PROCESSPBI"
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
    <#
    .SYNOPSIS
    Retrieves data from a Power BI REST endpoint.

    .DESCRIPTION
    Calls a Power BI admin endpoint and optionally pages through results
    using 5000-row batches, returning combined results as JSON.
    #>
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

    # Continue requesting pages until a page returns fewer than 5000 records.
    while ($returnCount -eq 5000) {
        Write-Log "Getting data from Power BI endpoint" -Level Debug -Data @{ Url = $newURL; Iteration = $iteration; Paged = $paged }
        try {
            $data = Invoke-PowerBIRestMethod -Url $newURL -Method Get | ConvertFrom-Json
        }
        catch {
            if (Test-IsHttp429Exception -ErrorRecord $_) {
                Write-Log "Power BI returned HTTP 429; stopping additional querying" -Level Fatal -Data @{ Url = $newURL }
                throw "Power BI API returned HTTP 429. Stopping additional querying."
            }
            throw
        }
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
    <#
    .SYNOPSIS
    Converts JSON rows into a typed DataTable.

    .DESCRIPTION
    Builds a DataTable from a schema definition string and maps JSON values
    into columns, including audit metadata used by downstream SQL loads.
    #>
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
            # Normalize null/array values so SQL bulk copy can persist rows reliably.
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
    <#
    .SYNOPSIS
    Executes a SQL query against the analytics database.

    .DESCRIPTION
    Runs read and write SQL via Invoke-Sqlcmd and enforces DryRun behavior
    by skipping write operations when dry-run mode is enabled.
    #>
    param (
        [string]$Query
    )

    $isWriteQuery = $Query -match '^(?is)\s*(INSERT|UPDATE|DELETE|TRUNCATE|MERGE|EXEC|CREATE|ALTER|DROP)\b'
    if ($DryRun -and $isWriteQuery) {
        Write-Log "DryRun enabled; skipping SQL write operation" -Level Information -Data @{ Query = $Query }
        return @()
    }

    Write-Log "Executing SQL query" -Level Debug -Data @{ Query = $Query }
    return Invoke-Sqlcmd -Query $Query -ConnectionString $connString
}

function Save-NotFoundRow {
    <#
    .SYNOPSIS
    Writes a marker row for missing or empty user results.

    .DESCRIPTION
    Inserts a single metadata row into a target table to indicate either an
    entity-not-found or no-users state for a given Power BI entity ID.
    #>
    param (
        [string]$TableName,
        [string]$IdColumn,
        [string]$IdValue,
        [string]$DisplayName,
        [string]$ApiUrl
    )

    $query = "INSERT INTO REPORTINGSERVICES.PBI.$TableName ($IdColumn, DisplayName, APIName, InsertDateTime, InsertBy) VALUES ('$IdValue', '$DisplayName', '$ApiUrl', GETDATE(), 'PBI.PS1')"
    Invoke-Sql -Query $query
}

function Transform-JsonPayload {
    <#
    .SYNOPSIS
    Applies named JSON transforms before table conversion.

    .DESCRIPTION
    Supports entity-specific transformations, such as flattening array fields
    for dataset payloads so rows can be persisted into scalar SQL columns.
    #>
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

function Test-IsHttp429Exception {
    <#
    .SYNOPSIS
    Detects Power BI throttling errors.

    .DESCRIPTION
    Evaluates an ErrorRecord for HTTP 429 by checking response status codes
    and fallback message text when typed response data is unavailable.
    #>
    param (
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return $false
    }

    $statusCode = $null

    if ($ErrorRecord.Exception -and $ErrorRecord.Exception.PSObject.Properties.Name -contains 'Response') {
        $response = $ErrorRecord.Exception.Response
        if ($response -and $response.PSObject.Properties.Name -contains 'StatusCode') {
            $statusCode = [int]$response.StatusCode
        }
    }

    if ($null -eq $statusCode -and $ErrorRecord.Exception -and $ErrorRecord.Exception.InnerException -and $ErrorRecord.Exception.InnerException.PSObject.Properties.Name -contains 'Response') {
        $innerResponse = $ErrorRecord.Exception.InnerException.Response
        if ($innerResponse -and $innerResponse.PSObject.Properties.Name -contains 'StatusCode') {
            $statusCode = [int]$innerResponse.StatusCode
        }
    }

    if ($statusCode -eq 429) {
        return $true
    }

    $message = $ErrorRecord.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message) -eq $false -and ($message -match '(?i)\b429\b|too many requests')) {
        return $true
    }

    return $false
}

function Sync-EntityUsers {
    <#
    .SYNOPSIS
    Synchronizes user access rows for Power BI entities.

    .DESCRIPTION
    Loads entity IDs from SQL, calls the related Power BI users endpoint,
    replaces existing rows, and writes optional marker rows for empty or
    not-found results based on configuration switches.
    #>
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
                # Stamp each returned user row with the owning entity key.
                $entityRow[$KeyColumn] = $row['id']
            }

            Invoke-Sql -Query "DELETE FROM REPORTINGSERVICES.PBI.$DeleteTable WHERE $NotFoundIdColumn = '$($row.Id)'"
            SaveToDatabase -data $entityUsers -table $SaveTable
            Write-Log "Saved users for entity" -Level Information -Data @{ EntityId = $row.Id; SaveTable = $SaveTable; Rows = $entityUsers.Rows.Count }

            if ($NoUsersInsertOnEmpty -and $entityUsers.Rows.Count -eq 0) {
                Save-NotFoundRow -TableName $NotFoundTable -IdColumn $NotFoundIdColumn -IdValue $row.Id -DisplayName $NoUsersText -ApiUrl $apiUrl
                Write-Log "Inserted no-users marker row" -Level Warning -Data @{ EntityId = $row.Id; Table = $NotFoundTable }
            }
        }
        catch {
            if ($_.Exception.Message -notlike '*PowerBIEntityNotFound*') {
                Write-Log "Error getting users for entity" -Level Error -Data @{ EntityId = $row.Id; SaveTable = $SaveTable; Message = $_.Exception.Message }
            }

            if (Test-IsHttp429Exception -ErrorRecord $_) {
                Write-Log "Power BI returned HTTP 429 while loading entity users; stopping additional querying" -Level Fatal -Data @{ EntityId = $row.Id; SaveTable = $SaveTable }
                throw "Power BI API returned HTTP 429. Stopping additional querying."
            }

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
    <#
    .SYNOPSIS
    Runs a configured user-entity synchronization.

    .DESCRIPTION
    Resolves a named entry from the user-entity configuration hashtable and
    passes settings into the shared Sync-EntityUsers workflow.
    #>
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
    <#
    .SYNOPSIS
    Loads a single admin entity into SQL.

    .DESCRIPTION
    Retrieves Power BI admin endpoint data, applies optional transforms,
    truncates target tables when requested, then bulk loads rows to SQL.
    #>
    param (
        [hashtable]$Config
    )

    Write-Log "Starting admin entity load" -Level Information -Data @{ Url = $Config.Url; TargetTable = $Config.TargetTable; Truncate = [bool]$Config.TruncateTarget }
    $api = Get-PBIData -url $Config.Url -paged $Config.Paged
    $api = Transform-JsonPayload -Name $Config.TransformName -Json $api
    $tableData = New-Table -tableDefinition $Config.TableDefinition -json $api -apiURL $Config.ApiUrl

    if ([bool]$Config.TruncateTarget) {
        Invoke-Sql -Query "TRUNCATE TABLE REPORTINGSERVICES.PBI.$($Config.TargetTable)"
    }

    SaveToDatabase -data $tableData -table $Config.TargetTable
    Write-Log "Completed admin entity load" -Level Information -Data @{ TargetTable = $Config.TargetTable; Rows = $tableData.Rows.Count }
}

function Invoke-AdminEntityLoad {
    <#
    .SYNOPSIS
    Runs a configured admin-entity load.

    .DESCRIPTION
    Resolves a named entry from the admin-entity configuration hashtable and
    executes the load routine for that entity.
    #>
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
    <#
    .SYNOPSIS
    Creates a DataTable schema from a definition string.

    .DESCRIPTION
    Parses comma-separated column definitions in the form columnName|type and
    builds a DataTable used for staged bulk-copy operations.
    #>
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
    <#
    .SYNOPSIS
    Bulk writes DataTable content to SQL Server.

    .DESCRIPTION
    Uses SqlBulkCopy to load rows into the target REPORTINGSERVICES.PBI table
    and honors DryRun mode by skipping the write operation.
    #>
    param (
        [System.Data.DataTable]$data,
        [string]$table
    )

    if ($DryRun) {
        Write-Log "DryRun enabled; skipping bulk copy write" -Level Information -Data @{ DestinationTable = "PBI.$table"; Rows = $data.Rows.Count }
        return
    }

    $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($connString)
    $bulkCopy.DestinationTableName = "REPORTINGSERVICES.PBI.$table"
    $bulkCopy.BulkCopyTimeout = 900
    Write-Log "Bulk copy write starting" -Level Debug -Data @{ DestinationTable = $bulkCopy.DestinationTableName; Rows = $data.Rows.Count }
    [void]$bulkCopy.WriteToServer($data)
    Write-Log "Bulk copy write completed" -Level Debug -Data @{ DestinationTable = $bulkCopy.DestinationTableName; Rows = $data.Rows.Count }
}

function Get-Activity {
    <#
    .SYNOPSIS
    Retrieves and stores activity events for a date range.

    .DESCRIPTION
    Calls Get-PowerBIActivityEvent for the provided window, converts the
    payload into a DataTable, and saves it to ActivityEvents.
    #>
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
    <#
    .SYNOPSIS
    Imports historical activity data from CSV.

    .DESCRIPTION
    Reads a CSV file containing AuditData payloads, expands each payload into
    the activity schema, and saves the results to TEMP_ActivityEvents.
    #>
    param (
        [string]$path
    )

    Write-Log "Importing activity file" -Level Information -Data @{ Path = $path }
    $p = Import-Csv -Path $path
    Write-Log "Imported CSV records" -Level Debug -Data @{ Count = $p.Count }
    $activity = GetActivityTable

    foreach ($row in $p) {
        # AuditData contains embedded JSON payloads that are expanded into table rows.
        Update-Table -table $activity -json $row.AuditData
    }

    SaveToDatabase -data $activity -table 'TEMP_ActivityEvents'
    Write-Log "Saved TEMP_ActivityEvents data" -Level Information -Data @{ Rows = $activity.Rows.Count }
}

# ══════════════════════════════════════════════════════════════════════════════
#  MODULES  — Load modules from the shared Modules folder, probing both
#             repo-root and subfolder launch contexts.
# ══════════════════════════════════════════════════════════════════════════════
function Import-LocalModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ModulesRoot
    )

    $availableModule = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.ModuleBase -like "$ModulesRoot*" } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $availableModule) {
        throw "Module '$Name' was not found under '$ModulesRoot'."
    }

    Import-Module -Name $availableModule.Path -ErrorAction Stop
}

$modulePathCandidates = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'modules'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'modules')
)

$modulesRoot = $modulePathCandidates |
    Where-Object { Test-Path -Path $_ -PathType Container } |
    Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($modulesRoot)) {
    throw "Local modules folder was not found. Checked: $($modulePathCandidates -join ', ')"
}

if (($env:PSModulePath -split ';') -notcontains $modulesRoot) {
    $env:PSModulePath = "$modulesRoot;$env:PSModulePath"
}

Import-LocalModule -Name 'PSLogger' -ModulesRoot $modulesRoot

Set-LogConfiguration -MinimumLevel $LogLevel -Console

Import-LocalModule -Name 'SecretStore' -ModulesRoot $modulesRoot

# ══════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════

function Invoke-PbiExportRun {
    <#
    .SYNOPSIS
    Orchestrates the full Power BI export run.

    .DESCRIPTION
    Loads secrets, authenticates to Power BI, backfills missing activity,
    refreshes configured entities, executes final SQL processing, and returns
    an exit code including handled throttling status.
    #>
    Write-Log "PBI export run started" -Level Information -Data @{ LogLevel = $LogLevel; DryRun = [bool]$DryRun; ConnectionStringName = $ConnectionStringName }

    $connectedToPowerBI = $false
    $exitCode = 0
    $secretStoreArgs = @{}

    # Only forward optional secret-store arguments when the script was launched with them.
    if ($MasterPassword) {
        $secretStoreArgs['MasterPassword'] = $MasterPassword
    }

    if ($SecretFile) {
        $secretStoreArgs['StoreFile'] = $SecretFile
    }

    try {

        # Resolve all runtime secrets required for SQL and service-principal auth.
        $connStringPath = "ConnectionStrings:$ConnectionStringName"
        $connString = Get-SecretValue @secretStoreArgs -Path $connStringPath
        $clientId = Get-SecretValue @secretStoreArgs -Path 'AZURE_AD_APP:CLIENTID'
        $clientSecret = Get-SecretValue @secretStoreArgs -Path 'AZURE_AD_APP:CLIENTSECRET'
        $tenantID = Get-SecretValue @secretStoreArgs -Path 'AZURE_AD_APP:TENANTID'
        
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

            # Backfill each missing day to keep ActivityEvents complete before refreshing dimension data.
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
        $exitCode = 0
    }
    catch {
        # Treat 429 as a handled throttle exit so schedulers can retry without surfacing a hard failure.
        if (Test-IsHttp429Exception -ErrorRecord $_) {
            $exitCode = 429
            Write-Log "Power BI API throttling encountered; run stopped gracefully" -Level Error -Data @{ ErrorCode = 'PBI429'; ExitCode = $exitCode; Message = $_.Exception.Message; Type = $_.Exception.GetType().FullName }
            Write-Log "PBI export run completed with handled throttling failure" -Level Warning -Data @{ ErrorCode = 'PBI429'; ExitCode = $exitCode }
        }
        else {
            Write-Log "Unhandled exception in PBI export run" -Level Fatal -Data @{ Message = $_.Exception.Message; Type = $_.Exception.GetType().FullName }
            throw
        }
    }
    finally {
        # Safety disconnect if an exception occurs after authentication succeeds.
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

    return $exitCode
}

# Return a non-zero process exit code when handled failures (like 429) occur.
$runExitCode = Invoke-PbiExportRun
if ($runExitCode -ne 0) {
    exit $runExitCode
}
