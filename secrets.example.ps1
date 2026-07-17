# Copy this file to secrets.ps1 and fill in the real values.
# secrets.ps1 is excluded from source control.

# Database connection string
$connString = "Server=<server>;Database=<database>;Integrated Security=True;TrustServerCertificate=True;"

# Azure AD App Registration credentials
$clientId     = "<azure-ad-client-id>"
$clientSecret = "<azure-ad-client-secret>"
$tenantID     = "<azure-ad-tenant-id>"
