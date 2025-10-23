---
description: This template creates an empty logic app that you can use to define workflows.
page_type: Kyos
products:
- azure
- azure-resource-manager
urlFragment: logic-app-create
languages:
- json
---
# Create an Admin Unit Auto Assignment logic app

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkyos-public%2Flogicapp-template%2Fmain%2Fkyos.logicapp%2Fadminunit.assignment%2FAssignResourcesToAU%2FAssignResourcesToAU.json)

## Prerequisites

Before deploying this template, ensure you have:

- **Azure subscription** with Logic Apps service enabled
- **App registrations** configured for Microsoft Graph API access
- **Azure Automation Account** with required runbooks
- **Required API permissions** granted in the target tenant:
  - `User.ReadWrite.All` (Microsoft Graph)
  - `Group.ReadWrite.All` (Microsoft Graph)
  - `AdministrativeUnit.ReadWrite.All` (Microsoft Graph)
  - `Device.ReadWrite.All` (Microsoft Graph)

## Template Parameters

### Required Parameters
- `logicAppName`: Name for the Logic App
- `authTenant`: Azure AD tenant ID
- `authClientId`: App registration client ID
- `authClientSecret`: App registration client secret
- `userPrefix`: Prefix for user filtering
- `userPattern`: Pattern for user filtering (e.g., "*@domain.com")

### Optional Parameters (with defaults)
- `extensionAttributeKey`: Extension attribute to check (default: "extensionAttribute1")
- `adminUnitId`: Target admin unit ID (default: empty)
- `extensionAttributeValue1/2/3`: Values to match against (defaults: "value1", "value2", "value3")
- `runbookName`: Azure Automation runbook name (default: "AssignUserToAdminUnit")
- `subscriptionId`: Azure subscription ID for Automation account
- `resourceGroupName`: Resource group containing Automation account
- `automationAccountName`: Name of the Azure Automation account

### Connection Parameters
- `connectionName`: Name of the Azure Automation connection (default: "kyos-azure-automation-connection")
- `useExistingConnection`: Whether to reuse an existing connection (default: false)

## Deployment Options

### Option 1: Create New Connection
Set `useExistingConnection` to `false` and provide Automation account details:
```json
{
  "useExistingConnection": {"value": false},
  "connectionName": {"value": "my-new-connection"},
  "subscriptionId": {"value": "your-subscription-id"},
  "resourceGroupName": {"value": "your-resource-group"},
  "automationAccountName": {"value": "your-automation-account"}
}
```

### Option 2: Reuse Existing Connection
Set `useExistingConnection` to `true` and provide the existing connection name:
```json
{
  "useExistingConnection": {"value": true},
  "connectionName": {"value": "existing-connection-name"}
}
```

## Minimal Deployment
For a minimal deployment, only provide:
- Authentication parameters (tenant, client ID, secret)
- User filtering parameters (prefix, pattern)
- Connection details (if creating new) or connection name (if reusing)


## Post-Deployment Steps

After the build of the logic app :
- Change the extensionAttribute on UsersRulesMapping variable to match with the real extensions attribute of the entity
- Adapt all parameters and variables with the current entity
- Change the runbook on the create job action to select the runbook of the dedicated entity


## Troubleshooting Connection Issues

If you encounter connection errors:

- **403 Forbidden**: Check if the app registration  has required Graph API permissions
- **400 Bad Request**: Verify syntax of URI property on HTTP actions

For information about using this template, see [Create Azure Resource Manager templates for Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-create-deploy-template). To learn more about how to deploy the template, see the [quickstart article](https://learn.microsoft.com/azure/logic-apps/quickstart-create-deploy-azure-resource-manager-template).
