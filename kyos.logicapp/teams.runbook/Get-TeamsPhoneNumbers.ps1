<#
.SYNOPSIS
    Azure Automation Runbook to retrieve all Teams phone numbers and their associated users/devices.

.DESCRIPTION
    This runbook connects to Microsoft Teams using a Managed Identity, retrieves all phone number assignments,
    and returns the data as JSON through a webhook response.

.NOTES
    Prerequisites:
    - Azure Automation Account with System-Assigned Managed Identity enabled
    - Managed Identity must have the following permissions:
      - Microsoft Graph: User.Read.All, Organization.Read.All
      - Teams Admin roles or appropriate Graph permissions for Teams
    - MicrosoftTeams PowerShell module installed in Automation Account

.PARAMETER WebhookData
    The webhook data object passed when the runbook is triggered via webhook.
#>

param (
    [Parameter(Mandatory = $false)]
    [object]$WebhookData
)

#region Functions
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] [$Level] $Message"
}

function Get-PhoneNumberAssignments {
    <#
    .SYNOPSIS
        Retrieves all Teams phone number assignments.
    .DESCRIPTION
        Gets all phone numbers assigned to users, devices, and voice applications.
    #>
    
    $results = @()
    
    try {
        # Get all phone number assignments
        Write-Log -Message "Retrieving Teams phone number assignments..." -Level Info
        
        # Get user phone numbers
        $users = Get-CsOnlineUser -Filter { LineURI -ne $null } -ErrorAction SilentlyContinue
        
        foreach ($user in $users) {
            $phoneNumber = $user.LineURI -replace "tel:", "" -replace ";.*", ""
            
            $results += [PSCustomObject]@{
                PhoneNumber      = $phoneNumber
                LineURI          = $user.LineURI
                AssignmentType   = "User"
                DisplayName      = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                ObjectId         = $user.Identity
                SipAddress       = $user.SipAddress
                EnterpriseVoiceEnabled = $user.EnterpriseVoiceEnabled
                TeamsCallingPolicy = $user.TeamsCallingPolicy
                OnlineVoiceRoutingPolicy = $user.OnlineVoiceRoutingPolicy
                TenantDialPlan   = $user.TenantDialPlan
                AssignedPlan     = "User Assignment"
                DeviceType       = $null
                Status           = "Assigned"
            }
        }
        
        Write-Log -Message "Found $($users.Count) user phone number assignments" -Level Info
        
        # Get voice application (Auto Attendant / Call Queue) phone numbers
        try {
            $voiceApps = Get-CsOnlineApplicationInstance -ErrorAction SilentlyContinue
            
            foreach ($app in $voiceApps) {
                if ($app.PhoneNumber) {
                    $phoneNumber = $app.PhoneNumber -replace "tel:", "" -replace ";.*", ""
                    
                    # Determine application type
                    $appType = "Voice Application"
                    if ($app.ApplicationId -eq "ce933385-9390-45d1-9512-c8d228074e07") {
                        $appType = "Auto Attendant"
                    }
                    elseif ($app.ApplicationId -eq "11cd3e2e-fccb-42ad-ad00-878b93575e07") {
                        $appType = "Call Queue"
                    }
                    
                    $results += [PSCustomObject]@{
                        PhoneNumber      = $phoneNumber
                        LineURI          = $app.PhoneNumber
                        AssignmentType   = $appType
                        DisplayName      = $app.DisplayName
                        UserPrincipalName = $app.UserPrincipalName
                        ObjectId         = $app.ObjectId
                        SipAddress       = $null
                        EnterpriseVoiceEnabled = $true
                        TeamsCallingPolicy = $null
                        OnlineVoiceRoutingPolicy = $null
                        TenantDialPlan   = $null
                        AssignedPlan     = $appType
                        DeviceType       = $null
                        Status           = "Assigned"
                    }
                }
            }
            
            Write-Log -Message "Found $($voiceApps.Count) voice application instances" -Level Info
        }
        catch {
            Write-Log -Message "Could not retrieve voice applications: $($_.Exception.Message)" -Level Warning
        }
        
        # Get Common Area Phones
        try {
            $commonAreaPhones = Get-CsOnlineUser -Filter { AccountType -eq "ResourceAccount" -and LineURI -ne $null } -ErrorAction SilentlyContinue
            
            foreach ($cap in $commonAreaPhones) {
                if ($cap.LineURI -and $cap.LineURI -notin $results.LineURI) {
                    $phoneNumber = $cap.LineURI -replace "tel:", "" -replace ";.*", ""
                    
                    $results += [PSCustomObject]@{
                        PhoneNumber      = $phoneNumber
                        LineURI          = $cap.LineURI
                        AssignmentType   = "Common Area Phone"
                        DisplayName      = $cap.DisplayName
                        UserPrincipalName = $cap.UserPrincipalName
                        ObjectId         = $cap.Identity
                        SipAddress       = $cap.SipAddress
                        EnterpriseVoiceEnabled = $cap.EnterpriseVoiceEnabled
                        TeamsCallingPolicy = $cap.TeamsCallingPolicy
                        OnlineVoiceRoutingPolicy = $cap.OnlineVoiceRoutingPolicy
                        TenantDialPlan   = $cap.TenantDialPlan
                        AssignedPlan     = "Common Area Phone"
                        DeviceType       = "Common Area Phone"
                        Status           = "Assigned"
                    }
                }
            }
            
            Write-Log -Message "Checked for Common Area Phones" -Level Info
        }
        catch {
            Write-Log -Message "Could not retrieve Common Area Phones: $($_.Exception.Message)" -Level Warning
        }
        
        # Get all phone numbers in inventory (assigned and unassigned)
        try {
            $allNumbers = Get-CsPhoneNumberAssignment -ErrorAction SilentlyContinue
            
            foreach ($number in $allNumbers) {
                # Check if this number is not already in results
                $existingEntry = $results | Where-Object { $_.PhoneNumber -eq $number.TelephoneNumber }
                
                if (-not $existingEntry) {
                    $results += [PSCustomObject]@{
                        PhoneNumber      = $number.TelephoneNumber
                        LineURI          = "tel:$($number.TelephoneNumber)"
                        AssignmentType   = if ($number.AssignedPstnTargetId) { "Assigned" } else { "Unassigned" }
                        DisplayName      = $number.AssignedPstnTargetId
                        UserPrincipalName = $null
                        ObjectId         = $number.AssignedPstnTargetId
                        SipAddress       = $null
                        EnterpriseVoiceEnabled = $null
                        TeamsCallingPolicy = $null
                        OnlineVoiceRoutingPolicy = $null
                        TenantDialPlan   = $null
                        AssignedPlan     = $number.NumberType
                        DeviceType       = $null
                        Status           = if ($number.AssignedPstnTargetId) { "Assigned" } else { "Available" }
                        City             = $number.City
                        NumberType       = $number.NumberType
                        CapabilityType   = $number.Capability
                        AcquisitionDate  = $number.AcquisitionDate
                    }
                }
                else {
                    # Update existing entry with additional info
                    $existingEntry | ForEach-Object {
                        $_ | Add-Member -NotePropertyName "City" -NotePropertyValue $number.City -Force -ErrorAction SilentlyContinue
                        $_ | Add-Member -NotePropertyName "NumberType" -NotePropertyValue $number.NumberType -Force -ErrorAction SilentlyContinue
                        $_ | Add-Member -NotePropertyName "CapabilityType" -NotePropertyValue $number.Capability -Force -ErrorAction SilentlyContinue
                        $_ | Add-Member -NotePropertyName "AcquisitionDate" -NotePropertyValue $number.AcquisitionDate -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            
            Write-Log -Message "Retrieved phone number inventory" -Level Info
        }
        catch {
            Write-Log -Message "Could not retrieve phone number inventory: $($_.Exception.Message)" -Level Warning
        }
        
    }
    catch {
        Write-Log -Message "Error retrieving phone numbers: $($_.Exception.Message)" -Level Error
        throw
    }
    
    return $results
}
#endregion Functions

#region Main
try {
    Write-Log -Message "Starting Teams Phone Number Retrieval Runbook" -Level Info
    
    # Check if running from webhook
    $isWebhook = $null -ne $WebhookData
    
    if ($isWebhook) {
        Write-Log -Message "Runbook triggered via webhook" -Level Info
        
        # Parse webhook body if needed
        if ($WebhookData.RequestBody) {
            $requestBody = $WebhookData.RequestBody | ConvertFrom-Json -ErrorAction SilentlyContinue
            Write-Log -Message "Webhook request body parsed" -Level Info
        }
    }
    
    # Connect to Microsoft Teams using Managed Identity
    Write-Log -Message "Connecting to Microsoft Teams using Managed Identity..." -Level Info
    
    try {
        # Connect using Managed Identity (System-assigned)
        Connect-MicrosoftTeams -Identity -ErrorAction Stop
        Write-Log -Message "Successfully connected to Microsoft Teams" -Level Info
    }
    catch {
        Write-Log -Message "Failed to connect using Managed Identity: $($_.Exception.Message)" -Level Error
        throw "Failed to connect to Microsoft Teams: $($_.Exception.Message)"
    }
    
    # Retrieve all phone number assignments
    $phoneNumbers = Get-PhoneNumberAssignments
    
    Write-Log -Message "Total phone numbers retrieved: $($phoneNumbers.Count)" -Level Info
    
    # Prepare response object
    $response = @{
        Success       = $true
        Timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        TotalCount    = $phoneNumbers.Count
        AssignedCount = ($phoneNumbers | Where-Object { $_.Status -eq "Assigned" }).Count
        UnassignedCount = ($phoneNumbers | Where-Object { $_.Status -eq "Available" }).Count
        Summary       = @{
            Users           = ($phoneNumbers | Where-Object { $_.AssignmentType -eq "User" }).Count
            AutoAttendants  = ($phoneNumbers | Where-Object { $_.AssignmentType -eq "Auto Attendant" }).Count
            CallQueues      = ($phoneNumbers | Where-Object { $_.AssignmentType -eq "Call Queue" }).Count
            CommonAreaPhones = ($phoneNumbers | Where-Object { $_.AssignmentType -eq "Common Area Phone" }).Count
            VoiceApplications = ($phoneNumbers | Where-Object { $_.AssignmentType -eq "Voice Application" }).Count
            Unassigned      = ($phoneNumbers | Where-Object { $_.Status -eq "Available" }).Count
        }
        PhoneNumbers  = $phoneNumbers
        Message       = "Successfully retrieved all Teams phone numbers"
    }
    
    # Convert to JSON
    $jsonResponse = $response | ConvertTo-Json -Depth 10 -Compress
    
    Write-Log -Message "Response prepared successfully" -Level Info
    
    # Disconnect from Teams
    try {
        Disconnect-MicrosoftTeams -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log -Message "Disconnected from Microsoft Teams" -Level Info
    }
    catch {
        Write-Log -Message "Warning: Could not disconnect cleanly: $($_.Exception.Message)" -Level Warning
    }
    
    # Output the JSON response (this will be captured by the webhook)
    Write-Output $jsonResponse
    
}
catch {
    Write-Log -Message "Runbook failed with error: $($_.Exception.Message)" -Level Error
    
    # Prepare error response
    $errorResponse = @{
        Success      = $false
        Timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        TotalCount   = 0
        PhoneNumbers = @()
        Message      = "Failed to retrieve Teams phone numbers"
        Error        = $_.Exception.Message
    }
    
    $jsonErrorResponse = $errorResponse | ConvertTo-Json -Depth 5 -Compress
    Write-Output $jsonErrorResponse
}
#endregion Main
