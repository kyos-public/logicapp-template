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

Before deploying this template to a new tenant, ensure you have:

- **Azure subscription** with Logic Apps service enabled
- **App registrations** configured for Microsoft Graph API access
- **Required API permissions** granted in the target tenant:
  - `User.ReadWrite.All` (Microsoft Graph)
  - `Group.ReadWrite.All` (Microsoft Graph)
  - `AdministrativeUnit.ReadWrite.All` (Microsoft Graph)
  - `Device.ReadWrite.All` (Microsoft Graph)


## Post-Deployment Steps


## Troubleshooting Connection Issues

If you encounter connection errors:

- **403 Forbidden**: Check if the app registration  has required Graph API permissions
- **400 Bad Request**: Verify syntax of URI property on HTTP actions

For information about using this template, see [Create Azure Resource Manager templates for Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-create-deploy-template). To learn more about how to deploy the template, see the [quickstart article](https://learn.microsoft.com/azure/logic-apps/quickstart-create-deploy-azure-resource-manager-template).
