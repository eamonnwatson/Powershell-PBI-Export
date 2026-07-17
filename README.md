# PBI Export

PowerShell script that pulls Power BI tenant metadata and activity logs via the Power BI Admin REST API and bulk-loads the results into a SQL Server database.

## What it does

On each run the script:

1. Connects to Power BI as a Service Principal.
2. Checks the most recent activity date stored in `PBI.ActivityEvents` and backfills missing days up to yesterday.
3. If any activity backfill was performed, it also refreshes all entity tables:
   - Workspaces/Groups → `PBI.Folders_Staging`
   - Apps → `PBI.Apps`
   - Reports → `PBI.Reports`
   - Datasets → `PBI.Datasets`
   - Capacity refresh schedules → `PBI.RefreshSchedule_Staging`
   - Capacities → `PBI.Capacities`
   - App users → `PBI.AppUsers`
4. Regardless of backfill, refreshes incremental user-access tables:
   - Report users → `PBI.ReportUsers` (top 100 reports not updated in 14 days, filtered to named capacities)
   - Workspace users → `PBI.FolderUsers` (filtered to named capacities)
   - Dataset users → `PBI.DatasetUsers` (top 100 datasets not updated in 14 days, filtered to named capacities)
5. Disconnects from Power BI.
6. Executes `EXEC PBI.SP_PROCESSPBI` to process the staged data.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| PowerShell | 5.1 (64-bit), Windows Server |
| Module | `MicrosoftPowerBIMgmt` (`Connect-PowerBIServiceAccount`, `Invoke-PowerBIRestMethod`, `Get-PowerBIActivityEvent`) |
| Module | `SqlServer` (`Invoke-Sqlcmd`) |
| SQL access | Windows Integrated Security to `SQL Server` |
| Azure AD | Service Principal with Power BI tenant admin API permissions |

Install the required modules if not already present:

```powershell
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser
Install-Module -Name SqlServer -Scope CurrentUser
```

## Configuration

Credentials and connection details are stored in `secrets.ps1`, which is excluded from source control. Copy `secrets.example.ps1` to `secrets.ps1` and fill in the real values:

```powershell
Copy-Item secrets.example.ps1 secrets.ps1
```

`secrets.ps1` must define:

- **`$clientId` / `$clientSecret` / `$tenantID`** - Azure AD Service Principal credentials.
- **`$connString`** - SQL Server connection string (uses Windows Integrated Security by default).

One additional value is hard-coded in the script itself:

- **Capacity GUIDs** - Two capacity IDs are hard-coded in the user-access queries to scope which workspaces/reports/datasets are processed.

## Key functions

| Function | Purpose |
|----------|---------|
| `Get-PBIData` | Calls a Power BI Admin REST endpoint, handling pagination in batches of 5,000 records. |
| `New-Table` | Converts a JSON API response into a typed `DataTable` using a column-definition string. |
| `GetTable` | Parses a `name\|type,...` column definition string into a `DataTable` schema. |
| `SaveToDatabase` | Bulk-copies a `DataTable` to a `PBI.<table>` target using `SqlBulkCopy`. |
| `Get-Groups` | Fetches all workspaces. |
| `Get-Apps` | Fetches all apps (truncates target before load). |
| `Get-Reports` | Fetches all reports (truncates target before load). |
| `Get-Datasets` | Fetches all datasets (truncates target before load). |
| `Get-Refresh` | Fetches capacity refreshable schedule data. |
| `Get-Capacity` | Fetches all capacities (truncates target before load). |
| `Get-Activity` | Fetches activity events for a single day window. |
| `Get-AppUsers` | Incrementally refreshes user access per app (skips apps updated in last 14 days). |
| `Get-ReportUsers` | Incrementally refreshes user access per report (scoped to named capacities). |
| `Get-GroupUsers` | Refreshes user access per workspace (scoped to named capacities). |
| `Get-DatasetUsers` | Incrementally refreshes user access per dataset (scoped to named capacities). |
| `Import-File` | Utility to import activity events from a CSV file into `PBI.TEMP_ActivityEvents`. |

## Database schema (PBI schema)

| Table | Load strategy |
|-------|--------------|
| `ActivityEvents` | Incremental append by date |
| `Folders_Staging` | Full replace (processed by stored procedure) |
| `Apps` | Truncate and reload |
| `Reports` | Truncate and reload |
| `Datasets` | Truncate and reload |
| `RefreshSchedule_Staging` | Full replace (processed by stored procedure) |
| `Capacities` | Truncate and reload |
| `AppUsers` | Delete per app + reload (14-day incremental) |
| `ReportUsers` | Delete per report + reload (14-day incremental) |
| `FolderUsers` | Delete per folder + reload |
| `DatasetUsers` | Delete per dataset + reload (14-day incremental) |

## Running the script

```powershell
# Run directly (SQL auth uses Windows Integrated Security automatically)
powershell.exe -ExecutionPolicy Bypass -File ".\PBI.ps1"
```

The script is intended to be scheduled daily (e.g. via SQL Server Agent or Windows Task Scheduler) after midnight so that the previous day's activity events are available.
