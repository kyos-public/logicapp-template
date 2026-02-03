# Teams Phone Numbers Runbook

This Azure Automation Runbook retrieves all Microsoft Teams phone numbers and their associated users, devices, or voice applications, returning the data as JSON through a webhook.

## Features

- Retrieves phone numbers assigned to **Users**
- Retrieves phone numbers assigned to **Auto Attendants**
- Retrieves phone numbers assigned to **Call Queues**
- Retrieves phone numbers assigned to **Common Area Phones**
- Lists **unassigned/available** phone numbers in inventory
- Returns comprehensive JSON response with summary statistics

## Prerequisites

### 1. Azure Automation Account

Create an Azure Automation Account if you don't have one:

```powershell
# Create Resource Group (if needed)
New-AzResourceGroup -Name "rg-automation" -Location "westeurope"

# Create Automation Account
New-AzAutomationAccount -ResourceGroupName "rg-automation" -Name "aa-teams-management" -Location "westeurope"
```

### 2. Enable System-Assigned Managed Identity

1. Navigate to your Automation Account in Azure Portal
2. Go to **Identity** under **Account Settings**
3. Enable **System assigned** managed identity
4. Click **Save**

### 3. Install Required PowerShell Modules

In your Automation Account:

1. Go to **Modules** under **Shared Resources**
2. Click **Browse Gallery**
3. Search and import the following modules:
   - `MicrosoftTeams` (latest version)

> **Note**: The MicrosoftTeams module installation may take several minutes.

### 4. Grant Permissions to Managed Identity

Run the following PowerShell script to grant the necessary permissions to your Automation Account's Managed Identity:

```powershell
# Grant-ManagedIdentityPermissions.ps1
# Run this from a machine with Az and Microsoft.Graph modules installed

param(
    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

# Connect to Azure and Microsoft Graph
Connect-AzAccount
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All", "RoleManagement.ReadWrite.Directory"

# Get the Automation Account's Managed Identity
$automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName
$managedIdentityObjectId = (Get-AzADServicePrincipal -DisplayName $AutomationAccountName).Id

# Get Microsoft Graph Service Principal
$graphApp = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"

# Required Graph permissions
$graphPermissions = @(
    "User.Read.All",
    "Organization.Read.All",
    "Directory.Read.All"
)

foreach ($permission in $graphPermissions) {
    $appRole = $graphApp.AppRoles | Where-Object { $_.Value -eq $permission }
    
    if ($appRole) {
        try {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $managedIdentityObjectId `
                -PrincipalId $managedIdentityObjectId `
                -ResourceId $graphApp.Id `
                -AppRoleId $appRole.Id `
                -ErrorAction SilentlyContinue
            
            Write-Host "Granted: $permission" -ForegroundColor Green
        }
        catch {
            Write-Host "Permission may already exist: $permission" -ForegroundColor Yellow
        }
    }
}

# Assign Teams Administrator role (or more specific role as needed)
$teamsAdminRoleId = (Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq 'Teams Administrator'").Id

New-MgRoleManagementDirectoryRoleAssignment `
    -PrincipalId $managedIdentityObjectId `
    -RoleDefinitionId $teamsAdminRoleId `
    -DirectoryScopeId "/"

Write-Host "Teams Administrator role assigned" -ForegroundColor Green
Write-Host "Permissions setup complete!" -ForegroundColor Cyan
```

### 5. Import the Runbook

1. Go to your Automation Account
2. Navigate to **Runbooks** under **Process Automation**
3. Click **Import a runbook**
4. Select `Get-TeamsPhoneNumbers.ps1`
5. Set **Runbook type** to `PowerShell`
6. Set **Runtime version** to `7.2` (recommended)
7. Click **Create**
8. Click **Publish** to make the runbook available

### 6. Create a Webhook

1. Open the published runbook
2. Click **Webhooks** in the left menu
3. Click **Add Webhook**
4. Click **Create new webhook**
5. Configure:
   - **Name**: `wh-get-teams-phone-numbers`
   - **Enabled**: Yes
   - **Expires**: Set appropriate expiration date
6. **Copy the webhook URL immediately** (it won't be shown again!)
7. Click **OK** and then **Create**

## Usage

### Calling the Webhook

#### Using PowerShell

```powershell
$webhookUrl = "https://xxxxxxxx.webhook.weu.azure-automation.net/webhooks?token=xxxxxxxxxx"

$response = Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "application/json"

# The response contains a job ID - you need to poll for results
$jobId = $response.JobIds[0]
```

#### Using curl

```bash
curl -X POST "https://xxxxxxxx.webhook.weu.azure-automation.net/webhooks?token=xxxxxxxxxx" \
     -H "Content-Type: application/json"
```

### Getting the Runbook Output

Since webhooks are asynchronous, you need to retrieve the job output:

```powershell
# Wait for job completion and get output
$resourceGroup = "rg-automation"
$automationAccount = "aa-teams-management"
$runbookName = "Get-TeamsPhoneNumbers"

# Poll until job completes
do {
    $job = Get-AzAutomationJob -ResourceGroupName $resourceGroup `
                               -AutomationAccountName $automationAccount `
                               -Id $jobId
    Start-Sleep -Seconds 5
} while ($job.Status -in @("New", "Activating", "Running"))

# Get the output
$output = Get-AzAutomationJobOutput -ResourceGroupName $resourceGroup `
                                    -AutomationAccountName $automationAccount `
                                    -Id $jobId `
                                    -Stream Output

# Parse JSON response
$phoneData = $output.Summary | ConvertFrom-Json
```

## Response Format

The runbook returns a JSON response with the following structure:

```json
{
  "Success": true,
  "Timestamp": "2026-02-03T10:30:00Z",
  "TotalCount": 150,
  "AssignedCount": 120,
  "UnassignedCount": 30,
  "Summary": {
    "Users": 100,
    "AutoAttendants": 5,
    "CallQueues": 10,
    "CommonAreaPhones": 5,
    "VoiceApplications": 0,
    "Unassigned": 30
  },
  "PhoneNumbers": [
    {
      "PhoneNumber": "+41441234567",
      "LineURI": "tel:+41441234567",
      "AssignmentType": "User",
      "DisplayName": "John Doe",
      "UserPrincipalName": "john.doe@contoso.com",
      "ObjectId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "SipAddress": "sip:john.doe@contoso.com",
      "EnterpriseVoiceEnabled": true,
      "TeamsCallingPolicy": "Global",
      "OnlineVoiceRoutingPolicy": null,
      "TenantDialPlan": null,
      "AssignedPlan": "User Assignment",
      "DeviceType": null,
      "Status": "Assigned",
      "City": "Zurich",
      "NumberType": "DirectRouting",
      "CapabilityType": "UserAssignment",
      "AcquisitionDate": "2024-01-15T00:00:00Z"
    }
  ],
  "Message": "Successfully retrieved all Teams phone numbers"
}
```

### Error Response

```json
{
  "Success": false,
  "Timestamp": "2026-02-03T10:30:00Z",
  "TotalCount": 0,
  "PhoneNumbers": [],
  "Message": "Failed to retrieve Teams phone numbers",
  "Error": "Error details here"
}
```

## Synchronous Webhook Response (Alternative)

If you need a synchronous response, consider using **Azure Functions** with an HTTP trigger instead, or create a Logic App that:

1. Receives the HTTP request
2. Triggers the runbook
3. Waits for completion
4. Returns the output

## Troubleshooting

### Common Issues

1. **"Failed to connect using Managed Identity"**
   - Ensure the System-assigned Managed Identity is enabled
   - Verify the MicrosoftTeams module is installed
   - Check that Teams Administrator role is assigned

2. **"Access Denied" or permission errors**
   - Verify all required permissions are granted to the Managed Identity
   - Allow up to 30 minutes for permission propagation

3. **Empty results**
   - Ensure your tenant has Teams Phone System licenses
   - Verify phone numbers are properly configured in Teams Admin Center

### Viewing Logs

1. Go to your Automation Account
2. Navigate to **Jobs** under **Process Automation**
3. Select the relevant job
4. View **All Logs** for detailed execution logs

## Security Considerations

- **Webhook URL**: Treat the webhook URL as a secret. Anyone with the URL can trigger the runbook.
- **Webhook Expiration**: Set appropriate expiration dates and rotate webhooks periodically.
- **Minimum Permissions**: Consider using more restrictive roles than Teams Administrator if possible.
- **Network Restrictions**: Consider using Private Endpoints for the Automation Account.

## Related Resources

- [Microsoft Teams PowerShell Module](https://docs.microsoft.com/en-us/microsoftteams/teams-powershell-overview)
- [Azure Automation Webhooks](https://docs.microsoft.com/en-us/azure/automation/automation-webhooks)
- [Managed Identities for Azure Automation](https://docs.microsoft.com/en-us/azure/automation/automation-security-overview#managed-identities)
