# PBI Export

PowerShell 5.1 script that pulls Power BI tenant metadata and activity logs via the Power BI Admin REST API and bulk-loads the results into SQL Server.

## What it does

On each run the script:

1. Loads required secrets from SecretStore (SQL connection string, client ID, client secret, tenant ID).
2. Connects to Power BI as a service principal.
3. Reads the latest date in PBI.ActivityEvents and compares it to yesterday.
4. If there is a gap, backfills each missing day of activity events.
5. If a gap was backfilled, also runs the full admin refresh block:
   - Workspaces/Groups -> PBI.Folders_Staging
   - Apps -> PBI.Apps
   - Reports -> PBI.Reports
   - Datasets -> PBI.Datasets
   - Capacity refresh schedules -> PBI.RefreshSchedule_Staging
   - Capacities -> PBI.Capacities
   - App users -> PBI.AppUsers
6. Always runs incremental user-access refreshes:
   - Report users -> PBI.ReportUsers (top 100 stale reports, scoped to configured capacities)
   - Workspace users -> PBI.FolderUsers (all workspaces in configured capacities)
   - Dataset users -> PBI.DatasetUsers (top 100 stale datasets, scoped to configured capacities)
7. Disconnects from Power BI.
8. Executes PBI.SP_PROCESSPBI.

If no activity gap is detected, the script skips step 5 and still runs steps 6 to 8.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| PowerShell | 5.1 (64-bit), Windows Server |
| Module | MicrosoftPowerBIMgmt (Connect-PowerBIServiceAccount, Invoke-PowerBIRestMethod, Get-PowerBIActivityEvent) |
| Module | SqlServer (Invoke-Sqlcmd) |
| Module | SecretStore (Get-Secret, Set-Secret, New-SecretStore) — see note below |
| Module | PSLogger (Write-Log, Set-LogConfiguration) — see note below |
| SQL access | Connection string from SecretStore (typically integrated security) |
| Azure AD | Service principal with Power BI tenant admin API permissions |

Install the publicly available modules if not already present:

```powershell
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser
Install-Module -Name SqlServer -Scope CurrentUser
```

> **Note:** SecretStore and PSLogger are custom modules authored by [Eamonn Watson](https://github.com/eamonnwatson) and are **not** available on the PowerShell Gallery. Clone or download them from GitHub before running the script:
>
> - SecretStore: https://github.com/eamonnwatson/SecretStore
> - PSLogger: https://github.com/eamonnwatson/PSLogger

## Configuration

Credentials and connection details are loaded from SecretStore.

Set the SecretStore password for the current session:

```powershell
$env:SECRETSTORE_PASSWORD = 'your-master-password'
```

Default secret paths used by the script:

- ConnectionStrings:AnalyticsSQL (SQL connection string)
- PBI:ClientID (Azure AD client ID)
- PBI:ClientSecret (Azure AD client secret)
- PBI:TenantID (Azure AD tenant ID)

### Script parameters

- -MasterPassword: SecretStore master password. If omitted, SECRETSTORE_PASSWORD is used.
- -StoreFile: Optional explicit SecretStore file path.
- -DryRun: Skips all SQL write operations (reads still execute). Useful for testing.
- -LogLevel: PSLogger minimum level. Allowed values are Trace, Debug, Information, Success, Warning, Error, Fatal. Default is Debug.

## Hard-coded scope filter

User-access refresh queries are restricted to two hard-coded capacity GUIDs via a script constant. Update the CapacityFilter variable in PBI.ps1 when this scope changes.

## Key functions

| Function | Purpose |
|----------|---------|
| Invoke-PbiExportRun | Main orchestration and error handling for the full run. |
| Get-PBIData | Calls a Power BI Admin REST endpoint and handles 5,000-row paging where applicable. |
| Load-AdminEntity / Invoke-AdminEntityLoad | Config-driven admin entity loads, including optional table truncation. |
| Sync-EntityUsers / Invoke-UserEntityLoad | Config-driven user-access loads with per-entity delete+reload behavior. |
| Transform-JsonPayload | Applies payload transforms (currently flattens dataset array fields). |
| Get-Activity | Loads one day of activity events into PBI.ActivityEvents. |
| New-Table / GetTable | Builds typed DataTable objects from API payloads and column definitions. |
| SaveToDatabase | Writes DataTable content to SQL via SqlBulkCopy. |
| Get-RequiredSecret | Retrieves and validates required SecretStore values. |
| Import-File | Helper to import CSV activity data into PBI.TEMP_ActivityEvents. |

## Database targets and load strategy

| Table | Load strategy |
|-------|--------------|
| ActivityEvents | Incremental append by date |
| Folders_Staging | Reloaded during full refresh block |
| Apps | Truncate and reload during full refresh block |
| Reports | Truncate and reload during full refresh block |
| Datasets | Truncate and reload during full refresh block |
| RefreshSchedule_Staging | Reloaded during full refresh block |
| Capacities | Truncate and reload during full refresh block |
| AppUsers | Delete per app plus reload (14-day stale app selection) during full refresh block |
| ReportUsers | Delete per report plus reload (14-day stale report selection, top 100), every run |
| FolderUsers | Delete per folder plus reload (capacity-filtered), every run |
| DatasetUsers | Delete per dataset plus reload (14-day stale dataset selection, top 100), every run |

Notes:

- ReportUsers and FolderUsers insert marker rows when no users are found or when the target entity is not found.
- DatasetUsers inserts marker rows when no users are found.

## Running the script

```powershell
# Run with SECRETSTORE_PASSWORD already set
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1"

# Run with explicit SecretStore password
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1" -MasterPassword "your-master-password"

# Run with a custom SecretStore file
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1" -StoreFile "D:\Secrets\pbi.store"

# Run in dry-run mode (no SQL writes)
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1" -DryRun

# Run with quieter logging
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1" -LogLevel Information
```

The script is intended to be scheduled daily (for example from SQL Server Agent or Windows Task Scheduler) shortly after midnight so the prior day activity window is available.
