# Grant API Permissions to Managed Identity
# This script grants required Microsoft Graph API permissions to a managed identity (system-assigned or user-assigned)
# using Microsoft Graph PowerShell module with enhanced functionality to find managed identities by name

param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityObjectId,
    
    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityName,
    
    [Parameter(Mandatory = $true)]
    [string[]]$ApiPermissions
)

# Required permissions for the Service Principal running this script (if using Service Principal auth):
# - Application.ReadWrite.All
# - AppRoleAssignment.ReadWrite.All
# - Directory.Read.All

function Connect-ToGraphAPI {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    try {
        # Check if Microsoft.Graph module is installed
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            Write-Error "Microsoft.Graph module is not installed. Please install it using: Install-Module Microsoft.Graph -Scope CurrentUser"
            return $false
        }
        
        # Import required modules
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Applications
        Import-Module Microsoft.Graph.Identity.DirectoryManagement
        
        if ($TenantId -and $ClientId -and $ClientSecret) {
            # Service Principal authentication
            Write-Host "Connecting to Microsoft Graph using Service Principal..." -ForegroundColor Yellow
            
            $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
            
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
        }
        else {
            # Interactive authentication
            Write-Host "Connecting to Microsoft Graph interactively..." -ForegroundColor Yellow
            
            # Connect with required scopes
            $scopes = @(
                "Application.ReadWrite.All", 
                "AppRoleAssignment.ReadWrite.All", 
                "Directory.Read.All"
            )
            
            Connect-MgGraph -Scopes $scopes -NoWelcome
        }
        
        # Verify connection
        $context = Get-MgContext
        if ($context) {
            Write-Host "Successfully connected to Microsoft Graph!" -ForegroundColor Green
            Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Cyan
            Write-Host "Account: $($context.Account)" -ForegroundColor Cyan
            return $true
        }
        else {
            throw "Failed to establish Graph context"
        }
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

function Get-MicrosoftGraphServicePrincipal {
    try {
        Write-Host "Getting Microsoft Graph Service Principal..." -ForegroundColor Yellow
        
        # Microsoft Graph App ID: 00000003-0000-0000-c000-000000000000
        $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
        
        if (-not $graphServicePrincipal) {
            throw "Microsoft Graph Service Principal not found"
        }
        
        Write-Host "Found Microsoft Graph Service Principal: $($graphServicePrincipal.DisplayName)" -ForegroundColor Green
        return $graphServicePrincipal
    }
    catch {
        Write-Error "Failed to get Microsoft Graph Service Principal: $($_.Exception.Message)"
        return $null
    }
}

function Find-ManagedIdentityByName {
    param([string]$Name)
    
    try {
        Write-Host "Searching for Managed Identity by name: $Name" -ForegroundColor Yellow
        
        # Search for service principals that match the name and are managed identities
        $servicePrincipals = Get-MgServicePrincipal -Filter "displayName eq '$Name'"
        
        if ($servicePrincipals.Count -eq 0) {
            # Try partial match if exact match fails
            Write-Host "Exact match not found, trying partial match..." -ForegroundColor Yellow
            $servicePrincipals = Get-MgServicePrincipal -Filter "startswith(displayName,'$Name')"
        }
        
        if ($servicePrincipals.Count -eq 0) {
            throw "No managed identity found with name '$Name'"
        }
        
        # Filter to only managed identities (they have specific servicePrincipalType)
        $managedIdentities = $servicePrincipals | Where-Object { 
            $_.ServicePrincipalType -eq "ManagedIdentity" -or 
            $_.Tags -contains "WindowsAzureActiveDirectoryIntegratedApp" 
        }
        
        if ($managedIdentities.Count -eq 0) {
            Write-Warning "Found service principals with name '$Name' but none appear to be managed identities"
            # Show what we found for troubleshooting
            foreach ($sp in $servicePrincipals) {
                Write-Host "  Found: $($sp.DisplayName) (Type: $($sp.ServicePrincipalType), AppId: $($sp.AppId))" -ForegroundColor Yellow
            }
            throw "No managed identities found with name '$Name'"
        }
        
        if ($managedIdentities.Count -gt 1) {
            Write-Host "Multiple managed identities found with name '$Name':" -ForegroundColor Yellow
            for ($i = 0; $i -lt $managedIdentities.Count; $i++) {
                $mi = $managedIdentities[$i]
                Write-Host "  [$i] $($mi.DisplayName) (ID: $($mi.Id), AppId: $($mi.AppId))" -ForegroundColor Cyan
            }
            
            # Use the first one but warn the user
            $selectedIdentity = $managedIdentities[0]
            Write-Warning "Using the first match: $($selectedIdentity.DisplayName)"
        }
        else {
            $selectedIdentity = $managedIdentities[0]
        }
        
        Write-Host "Found Managed Identity: $($selectedIdentity.DisplayName) (ID: $($selectedIdentity.Id))" -ForegroundColor Green
        return $selectedIdentity
    }
    catch {
        Write-Error "Failed to find managed identity by name: $($_.Exception.Message)"
        return $null
    }
}

function Get-ManagedIdentityServicePrincipal {
    param(
        [string]$ObjectId,
        [string]$Name
    )
    
    try {
        if ($ObjectId) {
            Write-Host "Getting Managed Identity by Object ID: $ObjectId" -ForegroundColor Yellow
            $managedIdentity = Get-MgServicePrincipal -ServicePrincipalId $ObjectId
        }
        elseif ($Name) {
            $managedIdentity = Find-ManagedIdentityByName -Name $Name
        }
        else {
            throw "Either ObjectId or Name must be provided"
        }
        
        if (-not $managedIdentity) {
            throw "Managed Identity not found"
        }
        
        Write-Host "Found Managed Identity: $($managedIdentity.DisplayName)" -ForegroundColor Green
        return $managedIdentity
    }
    catch {
        Write-Error "Failed to get Managed Identity Service Principal: $($_.Exception.Message)"
        return $null
    }
}

function Get-AppRoleByValue {
    param(
        [object]$ServicePrincipal,
        [string]$RoleValue
    )
    
    $appRole = $ServicePrincipal.AppRoles | Where-Object { $_.Value -eq $RoleValue }
    if ($appRole) {
        return $appRole
    }
    else {
        Write-Warning "App role '$RoleValue' not found in service principal '$($ServicePrincipal.DisplayName)'"
        
        # Show available calendar-related permissions for troubleshooting
        Write-Host "`nAvailable Calendar-related permissions:" -ForegroundColor Yellow
        $calendarRoles = $ServicePrincipal.AppRoles | Where-Object { $_.Value -like "*Calendar*" } | Sort-Object Value
        if ($calendarRoles.Count -gt 0) {
            foreach ($role in $calendarRoles) {
                Write-Host "  • $($role.Value) - $($role.DisplayName)" -ForegroundColor Cyan
            }
        }
        else {
            Write-Host "  No calendar-related permissions found." -ForegroundColor Gray
            Write-Host "`nSuggested alternatives for calendar access:" -ForegroundColor Yellow
            Write-Host "  • Calendars.Read - Read user calendars" -ForegroundColor Cyan
            Write-Host "  • Calendars.ReadWrite - Read and write user calendars" -ForegroundColor Cyan
        }
        
        return $null
    }
}

function Test-ExistingAppRoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$ResourceId,
        [string]$AppRoleId
    )
    
    try {
        $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId
        $existingAssignment = $assignments | Where-Object { 
            $_.ResourceId -eq $ResourceId -and $_.AppRoleId -eq $AppRoleId 
        }
        
        return ($null -ne $existingAssignment)
    }
    catch {
        Write-Warning "Failed to check existing app role assignment: $($_.Exception.Message)"
        return $false
    }
}

function Grant-AppRoleToManagedIdentity {
    param(
        [string]$ManagedIdentityId,
        [string]$ResourceServicePrincipalId,
        [string]$AppRoleId,
        [string]$PermissionName
    )
    
    try {
        # Check if permission is already granted
        if (Test-ExistingAppRoleAssignment -PrincipalId $ManagedIdentityId -ResourceId $ResourceServicePrincipalId -AppRoleId $AppRoleId) {
            Write-Host "    ✓ Permission '$PermissionName' already granted" -ForegroundColor Yellow
            return $true
        }
        
        Write-Host "  Granting permission: $PermissionName" -ForegroundColor Cyan
        
        # Create the app role assignment using Microsoft Graph PowerShell
        $assignment = @{
            PrincipalId = $ManagedIdentityId
            ResourceId = $ResourceServicePrincipalId
            AppRoleId = $AppRoleId
        }
        
        $null = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityId -BodyParameter $assignment
        
        Write-Host "    ✓ Successfully granted permission: $PermissionName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "    ✗ Failed to grant permission '$PermissionName': $($_.Exception.Message)"
        
        # Log detailed error information
        if ($_.Exception.Response) {
            Write-Host "      Error details: $($_.Exception.Response.StatusCode) - $($_.Exception.Response.ReasonPhrase)" -ForegroundColor Red
        }
        return $false
    }
}

function Grant-ManagedIdentityApiPermissions {
    param(
        [string]$ManagedIdentityObjectId,
        [string]$ManagedIdentityName,
        [string[]]$ApiPermissions
    )
    
    try {
        Write-Host "Granting API permissions to Managed Identity..." -ForegroundColor Yellow
        
        # Get Microsoft Graph Service Principal
        $graphServicePrincipal = Get-MicrosoftGraphServicePrincipal
        if (-not $graphServicePrincipal) {
            throw "Failed to get Microsoft Graph Service Principal"
        }
        
        # Get Managed Identity Service Principal
        $managedIdentity = Get-ManagedIdentityServicePrincipal -ObjectId $ManagedIdentityObjectId -Name $ManagedIdentityName
        if (-not $managedIdentity) {
            throw "Failed to get Managed Identity Service Principal"
        }
        
        $successCount = 0
        $failureCount = 0
        $invalidPermissions = @()
        
        foreach ($permission in $ApiPermissions) {
            Write-Host "`nProcessing permission: $permission" -ForegroundColor White
            
            # Get the app role for this permission
            $appRole = Get-AppRoleByValue -ServicePrincipal $graphServicePrincipal -RoleValue $permission
            if (-not $appRole) {
                Write-Warning "  Skipping unknown permission: $permission"
                $failureCount++
                $invalidPermissions += $permission
                continue
            }
            
            # Grant the permission
            if (Grant-AppRoleToManagedIdentity -ManagedIdentityId $managedIdentity.Id -ResourceServicePrincipalId $graphServicePrincipal.Id -AppRoleId $appRole.Id -PermissionName $permission) {
                $successCount++
            }
            else {
                $failureCount++
            }
        }
        
        # Show available permissions if there were invalid ones
        if ($invalidPermissions.Count -gt 0) {
            Write-Host "`n" + "="*60 -ForegroundColor Red
            Write-Host "INVALID PERMISSIONS DETECTED" -ForegroundColor Red
            Write-Host "="*60 -ForegroundColor Red
            Write-Host "The following permissions are not valid Microsoft Graph application permissions:" -ForegroundColor Yellow
            foreach ($invalidPerm in $invalidPermissions) {
                Write-Host "  ✗ $invalidPerm" -ForegroundColor Red
            }
            
            Write-Host "`nShowing available calendar-related permissions..." -ForegroundColor Yellow
            Show-AvailablePermissions -ServicePrincipal $graphServicePrincipal -FilterKeyword "Calendar"
        }
        
        Write-Host "`nPermission granting completed:" -ForegroundColor Magenta
        Write-Host "  Success: $successCount" -ForegroundColor Green
        Write-Host "  Failures: $failureCount" -ForegroundColor $(if ($failureCount -eq 0) { "Green" } else { "Red" })
        
        return @{
            SuccessCount = $successCount
            FailureCount = $failureCount
            ManagedIdentityName = $managedIdentity.DisplayName
            ManagedIdentityId = $managedIdentity.Id
        }
    }
    catch {
        Write-Error "Failed to grant API permissions: $($_.Exception.Message)"
        return @{
            SuccessCount = 0
            FailureCount = $ApiPermissions.Count
            ManagedIdentityName = "Unknown"
            ManagedIdentityId = if ($ManagedIdentityObjectId) { $ManagedIdentityObjectId } else { "Unknown" }
        }
    }
}

function Write-PermissionsSummary {
    param(
        [hashtable]$Results,
        [string[]]$RequestedPermissions,
        [string]$ManagedIdentityObjectId,
        [string]$ManagedIdentityName
    )
    
    Write-Host "`n" + "="*80 -ForegroundColor Magenta
    Write-Host "API PERMISSIONS GRANT SUMMARY" -ForegroundColor Magenta
    Write-Host "="*80 -ForegroundColor Magenta
    
    Write-Host "Managed Identity: $($Results.ManagedIdentityName)" -ForegroundColor White
    if ($ManagedIdentityObjectId) {
        Write-Host "Object ID: $ManagedIdentityObjectId" -ForegroundColor White
    }
    if ($ManagedIdentityName) {
        Write-Host "Search Name: $ManagedIdentityName" -ForegroundColor White
    }
    Write-Host "Requested Permissions: $($RequestedPermissions.Count)" -ForegroundColor White
    Write-Host "Successfully Granted: $($Results.SuccessCount)" -ForegroundColor Green
    Write-Host "Failed to Grant: $($Results.FailureCount)" -ForegroundColor $(if ($Results.FailureCount -eq 0) { "Green" } else { "Red" })
    
    Write-Host "`nRequested Permissions:" -ForegroundColor Yellow
    foreach ($permission in $RequestedPermissions) {
        Write-Host "  • $permission" -ForegroundColor Cyan
    }
    
    Write-Host "`nScript completed successfully!" -ForegroundColor Green
    Write-Host "="*80 -ForegroundColor Magenta
}

function Show-AvailablePermissions {
    param(
        [object]$ServicePrincipal,
        [string]$FilterKeyword = ""
    )
    
    try {
        Write-Host "`nAvailable Microsoft Graph Application Permissions:" -ForegroundColor Magenta
        
        $permissions = $ServicePrincipal.AppRoles | Sort-Object Value
        
        if ($FilterKeyword) {
            $permissions = $permissions | Where-Object { $_.Value -like "*$FilterKeyword*" -or $_.DisplayName -like "*$FilterKeyword*" }
            Write-Host "Filtered by keyword: '$FilterKeyword'" -ForegroundColor Yellow
        }
        
        if ($permissions.Count -eq 0) {
            Write-Host "No permissions found matching the filter." -ForegroundColor Gray
            return
        }
        
        Write-Host "Found $($permissions.Count) permissions:" -ForegroundColor Green
        Write-Host ""
        
        foreach ($permission in $permissions) {
            Write-Host "Permission: $($permission.Value)" -ForegroundColor Cyan
            Write-Host "  Description: $($permission.DisplayName)" -ForegroundColor White
            Write-Host "  Detailed Description: $($permission.Description)" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Error "Failed to show available permissions: $($_.Exception.Message)"
    }
}

# Main execution
try {
    Write-Host "Starting API Permissions Grant Script..." -ForegroundColor Magenta
    
    # Validate input parameters
    if (-not $ManagedIdentityObjectId -and -not $ManagedIdentityName) {
        throw "Either ManagedIdentityObjectId or ManagedIdentityName must be provided"
    }
    
    if ($ManagedIdentityObjectId) {
        Write-Host "Managed Identity Object ID: $ManagedIdentityObjectId" -ForegroundColor White
    }
    if ($ManagedIdentityName) {
        Write-Host "Managed Identity Name: $ManagedIdentityName" -ForegroundColor White
    }
    Write-Host "Permissions to Grant: $($ApiPermissions -join ', ')" -ForegroundColor White
    
    # Connect to Microsoft Graph
    if (-not (Connect-ToGraphAPI -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    # Grant API permissions
    $results = Grant-ManagedIdentityApiPermissions -ManagedIdentityObjectId $ManagedIdentityObjectId -ManagedIdentityName $ManagedIdentityName -ApiPermissions $ApiPermissions
    
    # Display summary
    Write-PermissionsSummary -Results $results -RequestedPermissions $ApiPermissions -ManagedIdentityObjectId $ManagedIdentityObjectId -ManagedIdentityName $ManagedIdentityName
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Yellow
    }
    catch {
        # Ignore disconnection errors
        Write-Host "Script execution completed." -ForegroundColor Yellow
    }
}

# Example usage:
<#
# Grant permissions using managed identity name (recommended):
.\Grant-ManagedIdentityApiPermissions.ps1 -ManagedIdentityName "my-logic-app" -ApiPermissions @("Group.Read.All", "User.Read.All", "Calendars.ReadWrite")

# Grant permissions using managed identity object ID:
.\Grant-ManagedIdentityApiPermissions.ps1 -ManagedIdentityObjectId "12345678-1234-1234-1234-123456789012" -ApiPermissions @("Group.Read.All", "User.Read.All", "Calendars.ReadWrite")

# Using Service Principal authentication:
.\Grant-ManagedIdentityApiPermissions.ps1 -TenantId "your-tenant-id" -ClientId "your-admin-client-id" -ClientSecret "your-admin-client-secret" -ManagedIdentityName "my-logic-app" -ApiPermissions @("Group.Read.All", "User.Read.All", "Calendars.ReadWrite")

# Grant other common permissions:
.\Grant-ManagedIdentityApiPermissions.ps1 -ManagedIdentityName "my-app" -ApiPermissions @("Directory.Read.All", "User.ReadWrite.All", "Group.ReadWrite.All")

# Common Calendar Permissions (APPLICATION PERMISSIONS):
# - Calendars.Read: Read calendars in all mailboxes
# - Calendars.ReadWrite: Read and write calendars in all mailboxes
# 
# Note: Calendars.ReadWrite.Shared does NOT exist as an application permission.
# For calendar sharing with external users, use Calendars.ReadWrite permission.

# Required Graph API Permissions for the Service Principal running this script (if using Service Principal auth):
# - Application.ReadWrite.All (to manage application permissions)
# - AppRoleAssignment.ReadWrite.All (to grant app role assignments)
# - Directory.Read.All (to read directory objects)

# Note: This script uses Microsoft Graph PowerShell module and supports both interactive and Service Principal authentication.
# If no authentication parameters are provided, it will use interactive authentication with the required scopes.
# The script can find managed identities by name or object ID.
#>
