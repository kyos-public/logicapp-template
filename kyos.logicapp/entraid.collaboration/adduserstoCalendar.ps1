# Grant Room Calendar Permissions to External Users from Group Guests
# This script retrieves guest users from a specified group, extracts their external email addresses,
# and grants read permissions to a room calendar for those external users.

param(
    [Parameter(Mandatory = $true)]
    [string]$GroupId,
    
    [Parameter(Mandatory = $true)]
    [string]$RoomEmailAddress,
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientSecret
)

# Required Graph API permissions:
# - Group.Read.All (to read group members)
# - User.Read.All (to read user details)
# - Calendars.ReadWrite.Shared (to manage calendar permissions)

function Connect-ToGraphAPI {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    try {
        if ($TenantId -and $ClientId -and $ClientSecret) {
            # Service Principal authentication
            Write-Host "Connecting to Microsoft Graph using Service Principal..." -ForegroundColor Yellow
            
            $body = @{
                Grant_Type    = "client_credentials"
                Scope         = "https://graph.microsoft.com/.default"
                Client_Id     = $ClientId
                Client_Secret = $ClientSecret
            }
            
            $connection = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body
            $global:headers = @{
                Authorization = "Bearer $($connection.access_token)"
                'Content-Type' = 'application/json'
            }
            Write-Host "Successfully connected to Microsoft Graph!" -ForegroundColor Green
        }
        else {
            # Interactive authentication using Microsoft.Graph module
            Write-Host "Connecting to Microsoft Graph interactively..." -ForegroundColor Yellow
            
            # Check if Microsoft.Graph module is installed
            if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
                Write-Error "Microsoft.Graph module is not installed. Please install it using: Install-Module Microsoft.Graph -Scope CurrentUser"
                return $false
            }
            
            # Import required modules
            Import-Module Microsoft.Graph.Authentication
            Import-Module Microsoft.Graph.Groups
            Import-Module Microsoft.Graph.Users
            Import-Module Microsoft.Graph.Calendar
            
            # Connect with required scopes
            Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "Calendars.ReadWrite.Shared"
            
            $global:useGraphModule = $true
            Write-Host "Successfully connected to Microsoft Graph!" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

function Get-GroupGuestUsers {
    param([string]$GroupId)
    
    try {
        Write-Host "Retrieving guest users from group: $GroupId" -ForegroundColor Yellow
        
        if ($global:useGraphModule) {
            # Using Microsoft.Graph module
            $members = Get-MgGroupMember -GroupId $GroupId -All
            $guestUsers = $members | Where-Object { $_.AdditionalProperties.userType -eq "Guest" }
            
            $guests = @()
            foreach ($guest in $guestUsers) {
                $userDetails = Get-MgUser -UserId $guest.Id -Property "id,mail,userPrincipalName,userType,displayName"
                $guests += $userDetails
            }
        }
        else {
            # Using REST API
            $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members?`$filter=userType eq 'Guest'&`$select=id,mail,userPrincipalName,userType,displayName"
            $response = Invoke-RestMethod -Uri $uri -Headers $global:headers -Method GET
            $guests = $response.value
            
            # Handle pagination if needed
            while ($response.'@odata.nextLink') {
                $response = Invoke-RestMethod -Uri $response.'@odata.nextLink' -Headers $global:headers -Method GET
                $guests += $response.value
            }
        }
        
        Write-Host "Found $($guests.Count) guest users in the group" -ForegroundColor Green
        return $guests
    }
    catch {
        Write-Error "Failed to retrieve guest users from group: $($_.Exception.Message)"
        return @()
    }
}

function Extract-ExternalEmailAddresses {
    param([array]$GuestUsers)
    
    try {
        Write-Host "Extracting external email addresses from guest users..." -ForegroundColor Yellow
        
        $externalEmails = @()
        
        foreach ($guest in $GuestUsers) {
            $externalEmail = $null
            
            # Try to get email from mail attribute first
            if ($guest.mail) {
                $externalEmail = $guest.mail
                Write-Host "  Found external email from mail attribute: $externalEmail" -ForegroundColor Cyan
            }
            # If no mail attribute, try to extract from userPrincipalName
            elseif ($guest.userPrincipalName -and $guest.userPrincipalName.Contains("#EXT#")) {
                # Guest UPN format: externaluser_domain.com#EXT#@tenant.onmicrosoft.com
                $upnParts = $guest.userPrincipalName.Split("#EXT#")[0]
                $externalEmail = $upnParts.Replace("_", "@")
                Write-Host "  Extracted external email from UPN: $externalEmail" -ForegroundColor Cyan
            }
            
            if ($externalEmail) {
                $externalEmails += @{
                    DisplayName = $guest.displayName
                    ExternalEmail = $externalEmail
                    GuestId = $guest.id
                }
            }
            else {
                Write-Warning "  Could not extract external email for guest: $($guest.displayName) ($($guest.userPrincipalName))"
            }
        }
        
        Write-Host "Successfully extracted $($externalEmails.Count) external email addresses" -ForegroundColor Green
        return $externalEmails
    }
    catch {
        Write-Error "Failed to extract external email addresses: $($_.Exception.Message)"
        return @()
    }
}

function Grant-CalendarPermissions {
    param(
        [array]$ExternalUsers,
        [string]$RoomEmailAddress
    )
    
    try {
        Write-Host "Granting calendar read permissions to external users for room: $RoomEmailAddress" -ForegroundColor Yellow
        
        $successCount = 0
        $failureCount = 0
        
        foreach ($user in $ExternalUsers) {
            try {
                Write-Host "  Granting permission to: $($user.ExternalEmail)" -ForegroundColor Cyan
                
                if ($global:useGraphModule) {
                    # Using Microsoft.Graph module
                    $permission = @{
                        EmailAddress = @{
                            Address = $user.ExternalEmail
                            Name = $user.DisplayName
                        }
                        Role = "read"
                    }
                    
                    # Note: Calendar permissions via Graph module might require different approach
                    # This is a placeholder for the Graph module method
                    Write-Warning "  Calendar permission granting via Graph module requires additional implementation"
                }
                else {
                    # Using REST API
                    $permissionBody = @{
                        emailAddress = @{
                            address = $user.ExternalEmail
                            name = $user.DisplayName
                        }
                        role = "read"
                    } | ConvertTo-Json -Depth 3
                    
                    $uri = "https://graph.microsoft.com/v1.0/users/$RoomEmailAddress/calendar/calendarPermissions"
                    $response = Invoke-RestMethod -Uri $uri -Headers $global:headers -Method POST -Body $permissionBody
                    
                    Write-Host "    ✓ Successfully granted read permission" -ForegroundColor Green
                    $successCount++
                }
            }
            catch {
                Write-Warning "    ✗ Failed to grant permission: $($_.Exception.Message)"
                $failureCount++
                
                # Log the specific error for troubleshooting
                Write-Host "      Error details: $($_.Exception.Response.StatusCode) - $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
            }
        }
        
        Write-Host "Permission granting completed: $successCount successful, $failureCount failed" -ForegroundColor $(if ($failureCount -eq 0) { "Green" } else { "Yellow" })
        
        return @{
            SuccessCount = $successCount
            FailureCount = $failureCount
        }
    }
    catch {
        Write-Error "Failed to grant calendar permissions: $($_.Exception.Message)"
        return @{
            SuccessCount = 0
            FailureCount = $ExternalUsers.Count
        }
    }
}

function Write-Summary {
    param(
        [array]$GuestUsers,
        [array]$ExternalUsers,
        [hashtable]$Results,
        [string]$GroupId,
        [string]$RoomEmailAddress
    )
    
    Write-Host "`n" + "="*80 -ForegroundColor Magenta
    Write-Host "EXECUTION SUMMARY" -ForegroundColor Magenta
    Write-Host "="*80 -ForegroundColor Magenta
    
    Write-Host "Group ID: $GroupId" -ForegroundColor White
    Write-Host "Room Calendar: $RoomEmailAddress" -ForegroundColor White
    Write-Host "Guest Users Found: $($GuestUsers.Count)" -ForegroundColor White
    Write-Host "External Emails Extracted: $($ExternalUsers.Count)" -ForegroundColor White
    Write-Host "Permissions Granted Successfully: $($Results.SuccessCount)" -ForegroundColor Green
    Write-Host "Permission Failures: $($Results.FailureCount)" -ForegroundColor $(if ($Results.FailureCount -eq 0) { "Green" } else { "Red" })
    
    if ($ExternalUsers.Count -gt 0) {
        Write-Host "`nExternal Users Processed:" -ForegroundColor Yellow
        foreach ($user in $ExternalUsers) {
            Write-Host "  • $($user.DisplayName) ($($user.ExternalEmail))" -ForegroundColor Cyan
        }
    }
    
    Write-Host "`nScript completed successfully!" -ForegroundColor Green
    Write-Host "="*80 -ForegroundColor Magenta
}

# Main execution
try {
    Write-Host "Starting Calendar Permission Script..." -ForegroundColor Magenta
    Write-Host "Group ID: $GroupId" -ForegroundColor White
    Write-Host "Room Email: $RoomEmailAddress" -ForegroundColor White
    
    # Connect to Microsoft Graph
    if (-not (Connect-ToGraphAPI -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret)) {
        throw "Failed to connect to Microsoft Graph API"
    }
    
    # Step 1: Get guest users from the group
    $guestUsers = Get-GroupGuestUsers -GroupId $GroupId
    if ($guestUsers.Count -eq 0) {
        Write-Warning "No guest users found in the specified group. Exiting script."
        return
    }
    
    # Step 2: Extract external email addresses
    $externalUsers = Extract-ExternalEmailAddresses -GuestUsers $guestUsers
    if ($externalUsers.Count -eq 0) {
        Write-Warning "No external email addresses could be extracted. Exiting script."
        return
    }
    
    # Step 3: Grant calendar permissions
    $results = Grant-CalendarPermissions -ExternalUsers $externalUsers -RoomEmailAddress $RoomEmailAddress
    
    # Step 4: Display summary
    Write-Summary -GuestUsers $guestUsers -ExternalUsers $externalUsers -Results $results -GroupId $GroupId -RoomEmailAddress $RoomEmailAddress
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
}
finally {
    # Disconnect from Graph if using module
    if ($global:useGraphModule) {
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Yellow
        }
        catch {
            # Ignore disconnection errors
        }
    }
}

# Example usage:
<#
# Using Service Principal authentication:
.\adduserstoCalendar.ps1 -GroupId "12345678-1234-1234-1234-123456789012" -RoomEmailAddress "room@company.com" -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-client-secret"

# Using interactive authentication:
.\adduserstoCalendar.ps1 -GroupId "12345678-1234-1234-1234-123456789012" -RoomEmailAddress "room@company.com"

# Required Graph API Permissions for Service Principal:
# - Group.Read.All
# - User.Read.All  
# - Calendars.ReadWrite.Shared
#>

# 1c6aa84d-9f9d-4178-997a-575ae9325969
# GE-FT32-RC-A-2P@speakhub.ch
# .\adduserstoCalendar.ps1 -GroupId "1c6aa84d-9f9d-4178-997a-575ae9325969" -RoomEmailAddress "GE-FT32-RC-A-2P@speakhub.ch"