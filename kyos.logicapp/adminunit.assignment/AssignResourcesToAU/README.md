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

## Overview

This Logic App template creates a workflow that automatically assigns users, groups, and devices to Azure AD Administrative Units. The template features a **parallel execution architecture** where user, group, and device assignments are processed simultaneously for optimal performance.

## Architecture

The workflow operates in three parallel branches after fetching user data from Azure Automation:

1. **Users Branch**: Processes users returned by the runbook
2. **Groups Branch**: Fetches and processes groups matching the user prefix
3. **Devices Branch**: Fetches and processes devices matching the user prefix

All three branches execute in parallel, improving overall execution time and efficiency.

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
- `adminUnitId`: Target Administrative Unit ID
- `userPrefix`: Prefix for filtering users, groups, and devices

### Optional Parameters (with defaults)
- `userPattern`: Pattern for user filtering (default: empty)
- `runbookName`: Azure Automation runbook name (default: empty)
- `resourceGroupName`: Resource group containing Automation account (default: "M365-TenantManagement")
- `automationAccountName`: Name of the Azure Automation account (default: "HES-M365-AzureAutomationAccount")
- `connectionName`: Name of the existing Azure Automation connection (default: "azureautomation")

**Note**: This template always uses an existing Azure Automation connection. Ensure the connection exists in your resource group before deploying.

## Minimal Deployment
For a minimal deployment, provide:
- Authentication parameters (tenant, client ID, secret)
- User filtering parameters (prefix, pattern)
- Connection name (must exist in the target resource group)


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
