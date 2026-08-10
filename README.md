# Power BI Admin Export to SQL Server

This script collects Power BI tenant admin metadata and activity events, then loads the results into SQL Server tables under REPORTINGSERVICES.PBI.

It is designed for PowerShell 5.1 on Windows Server and uses local helper modules for logging and secret retrieval.

## What the script does

The script runs as a six-phase pipeline:

1. Local module bootstrap and logging setup
2. SecretStore and authentication setup
3. Activity gap check and optional day-by-day backfill
4. Conditional full admin refresh block
5. Incremental user access refresh block
6. Final SQL processing and exit code handling

Key behaviors:

- Connects to Power BI using a service principal.
- Checks the latest date in REPORTINGSERVICES.PBI.ActivityEvents against yesterday.
- Backfills each missing day using Get-PowerBIActivityEvent when a gap exists.
- Loads admin entities through config-driven endpoint definitions.
- Refreshes ReportUsers, GroupUsers, and DatasetUsers every run.
- Stops querying immediately when Power BI returns HTTP 429 and exits with code 429.
- Supports dry-run mode that skips all SQL write operations while still running API calls and SQL reads.

## Prerequisites

- Windows host running PowerShell 5.1 (64-bit).
- Access to Power BI Admin APIs using a service principal.
- SQL Server connectivity for REPORTINGSERVICES.PBI tables and stored procedures.
- Public modules installed:
   - MicrosoftPowerBIMgmt
   - SqlServer
- Local modules folder containing:
   - PSLogger
   - SecretStore

Install public modules if needed:

```powershell
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser
Install-Module -Name SqlServer -Scope CurrentUser
```

The script probes for local modules under one of these locations:

- .\modules
- ..\modules

## Required parameters

- ConnectionStringName: SecretStore key name under ConnectionStrings: used to get the SQL connection string.

Optional parameters:

- -f or -SecretFile: SecretStore file path.
- -p or -MasterPassword: SecretStore master password as SecureString.
- -d or -DryRun: run all read and API steps, but skip SQL writes.
- -LogLevel: Trace, Debug, Information, Success, Warning, Error, Fatal.

Default log level is Warning.

## Runtime configuration defaults

The script includes top-level defaults and config maps:

- ErrorActionPreference = Stop
- CapacityFilter contains two hard-coded capacity GUIDs
- SqlQueries map defines select and process statements
- AdminEntities map defines endpoint URLs, paging mode, and SQL targets
- UserEntities map defines select queries, user endpoints, and marker-row behavior

Endpoint paging default:

- Paged admin endpoints use top = 5000 with skip iteration.

## SecretStore keys used

The script resolves these required key paths from SecretStore:

- ConnectionStrings:{ConnectionStringName}
- AZURE_AD_APP:CLIENTID
- AZURE_AD_APP:CLIENTSECRET
- AZURE_AD_APP:TENANTID

## Quick start

Run a normal export:

```powershell
.\PBI.ps1 -ConnectionStringName AnalyticsSQL
```

Run with explicit SecretStore file and master password:

```powershell
$pw = Read-Host 'Secret store master password' -AsSecureString

.\PBI.ps1 `
   -ConnectionStringName AnalyticsSQL `
   -SecretFile C:\Secrets\pbi.store `
   -MasterPassword $pw
```

Run in dry-run mode:

```powershell
.\PBI.ps1 -ConnectionStringName AnalyticsSQL -DryRun
```

Run with more verbose logging:

```powershell
.\PBI.ps1 -ConnectionStringName AnalyticsSQL -LogLevel Information
```

In dry-run mode:

- SQL read queries still run.
- Power BI API calls still run.
- SQL write actions are skipped, including DELETE, TRUNCATE, EXEC, INSERT, and bulk copy writes.

## Phase details

### Phase A: Module bootstrap and logger setup

- Resolves modules root from .\modules or ..\modules.
- Adds modules root to PSModulePath if needed.
- Imports PSLogger and SecretStore from the local modules folder.
- Initializes console logging with the selected log level.

### Phase B: Secret load and Power BI sign-in

- Reads required secrets from SecretStore.
- Builds PSCredential from CLIENTID and CLIENTSECRET.
- Connects with Connect-PowerBIServiceAccount using service principal auth.

### Phase C: Activity gap detection and backfill

- Reads max activity date from REPORTINGSERVICES.PBI.ActivityEvents.
- Compares it to yesterday.
- If max date is behind, loads each missing day using:
   - StartDateTime: yyyy-MM-ddT00:00:00
   - EndDateTime: yyyy-MM-ddT23:59:59
- Writes results into REPORTINGSERVICES.PBI.ActivityEvents.

### Phase D: Full admin refresh block (only when a gap exists)

Runs these entity loads:

- Reports -> REPORTINGSERVICES.PBI.Reports (truncate + reload)
- Groups -> REPORTINGSERVICES.PBI.Folders_Staging (reload)
- Apps -> REPORTINGSERVICES.PBI.Apps (truncate + reload)
- Datasets -> REPORTINGSERVICES.PBI.Datasets (truncate + reload)
- Refresh -> REPORTINGSERVICES.PBI.RefreshSchedule_Staging (reload)
- Capacity -> REPORTINGSERVICES.PBI.Capacities (truncate + reload)
- AppUsers -> REPORTINGSERVICES.PBI.AppUsers (per-app delete + reload for stale apps)

Entity paging behavior:

- Paged endpoints request 5000 rows per call with top/skip pagination.
- Capacities endpoint is not paged.

### Phase E: Incremental user access refresh (every run)

Runs these syncs every execution:

- ReportUsers -> REPORTINGSERVICES.PBI.ReportUsers
- GroupUsers -> REPORTINGSERVICES.PBI.FolderUsers
- DatasetUsers -> REPORTINGSERVICES.PBI.DatasetUsers

Selection scope and behavior:

- ReportUsers and DatasetUsers use top 100 stale IDs from SQL.
- GroupUsers uses all workspace IDs in the configured capacity filter.
- Existing rows for each entity ID are deleted before reinsert.
- Marker rows are written for configured no-users and not-found scenarios.

### Phase F: Final processing and exit behavior

- Disconnects from Power BI.
- Executes REPORTINGSERVICES.PBI.SP_PROCESSPBI.
- Returns process exit code:
   - 0 on success
   - 429 when throttling is detected and handled

Handled throttling behavior:

- HTTP 429 is treated as a scheduler-friendly handled failure.
- The script logs the throttle event and exits with code 429.

## API endpoints used

- https://api.powerbi.com/v1.0/myorg/admin/groups
- https://api.powerbi.com/v1.0/myorg/admin/apps
- https://api.powerbi.com/v1.0/myorg/admin/reports
- https://api.powerbi.com/v1.0/myorg/admin/datasets
- https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables
- https://api.powerbi.com/v1.0/myorg/admin/capacities
- https://api.powerbi.com/v1.0/myorg/admin/apps/{id}/users
- https://api.powerbi.com/v1.0/myorg/admin/reports/{id}/users
- https://api.powerbi.com/v1.0/myorg/admin/groups/{id}/users
- https://api.powerbi.com/v1.0/myorg/admin/datasets/{id}/users
- https://api.powerbi.com/v1.0/myorg/admin/activityevents

## SQL objects touched

Primary load targets:

- REPORTINGSERVICES.PBI.ActivityEvents
- REPORTINGSERVICES.PBI.Folders_Staging
- REPORTINGSERVICES.PBI.Apps
- REPORTINGSERVICES.PBI.Reports
- REPORTINGSERVICES.PBI.Datasets
- REPORTINGSERVICES.PBI.RefreshSchedule_Staging
- REPORTINGSERVICES.PBI.Capacities
- REPORTINGSERVICES.PBI.AppUsers
- REPORTINGSERVICES.PBI.ReportUsers
- REPORTINGSERVICES.PBI.FolderUsers
- REPORTINGSERVICES.PBI.DatasetUsers

Final processing command:

- EXEC REPORTINGSERVICES.PBI.SP_PROCESSPBI

## Capacity filter scope

Some user refresh SQL queries are scoped to two hard-coded capacity IDs in the script:

- 41DC39CE-E61D-4E09-A26B-2FCB5D6D8DFE
- 027965A4-D372-461A-862D-B0435B1A1FB0

If tenant scope changes, update the CapacityFilter constant in the script.

## Operational notes

- This script is intended to run daily after midnight so the previous day activity window is complete.
- Script files should remain ASCII-only for PowerShell 5.1 compatibility.
- HTTP 429 is treated as a handled scheduler-friendly failure with exit code 429.

## Troubleshooting checklist

1. Verify local modules folder exists and contains PSLogger and SecretStore.
2. Verify MicrosoftPowerBIMgmt and SqlServer modules are installed.
3. Verify SecretStore contains all required keys listed above.
4. Verify service principal has required Power BI admin API permissions.
5. Verify SQL login and connection string resolve to the expected REPORTINGSERVICES database.
6. Use -LogLevel Debug to increase diagnostic output.
