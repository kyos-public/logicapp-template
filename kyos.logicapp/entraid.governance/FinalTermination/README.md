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
# Create an EntraID provisioning logic app

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkyos-public%2Flogicapp-template%2Fmain%2Fkyos.logicapp%2Fentraid.governance%2FFinalTermination%2FFinalTermination.json)

## Prerequisites

Before deploying this template to a new tenant, ensure you have:

- **Azure subscription** with Logic Apps service enabled
- **Managed Identity permissions** configured for comprehensive user management
- **Required API permissions** granted in the target tenant:
  - `User.ReadWrite.All` (Microsoft Graph)
  - `Directory.ReadWrite.All` (Microsoft Graph)
  - `Group.ReadWrite.All` (Microsoft Graph)
  - `Application.ReadWrite.All` (Microsoft Graph)
- **Global Administrator** or equivalent permissions for user termination operations

## Connection Configuration

This template uses managed identity for secure authentication. After deployment, you may need to:

1. **Configure Managed Identity**: Ensure the Logic App's system-assigned managed identity has comprehensive permissions
2. **Update API Connections**: Verify all API connections are properly authenticated in the target tenant
3. **Multi-service Integration**: Ensure connections to all required services (AD, Exchange, Teams, etc.) are configured
4. **Grant Admin Consent**: Final termination requires extensive admin consent in the target tenant

Azure Logic Apps is a cloud service that automates the execution of your business processes. You can create a workflow by using a visual designer to arrange prebuilt components into the sequence that you need. When you save your workflow, the designer sends the workflow's definition to the Azure Logic Apps execution engine. When the conditions for the workflow's trigger are met, the engine launches the workflow and manages the compute resources that the workflow needs to run. If you're new to Azure Logic Apps, see [What is Azure Logic Apps?](https://learn.microsoft.com/azure/logic-apps/logic-apps-overview).

This quickstart template create a workflow for the Final Termination.

## Post-Deployment Steps

1. Navigate to the deployed Logic App in the Azure portal
2. Go to **Identity** section and note the Object ID of the system-assigned managed identity
3. In **Azure Active Directory > Enterprise Applications**, find the managed identity and assign all required permissions
4. Verify integration with all target services (Exchange, Teams, SharePoint, etc.)
5. Test the workflow in a non-production environment first
6. Set up appropriate approval workflows for final termination operations

## Troubleshooting Connection Issues

If you encounter connection errors:

- **403 Forbidden**: Check if managed identity has all required permissions for user termination
- **401 Unauthorized**: Verify API connections are authenticated for the target tenant
- **Service Integration Errors**: Verify connectivity to Exchange, Teams, and other integrated services
- **Permission Denied**: Ensure Global Administrator level permissions are granted
- **Connection not found**: Recreate API connections in the Logic App designer

For information about using this template, see [Create Azure Resource Manager templates for Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-create-deploy-template). To learn more about how to deploy the template, see the [quickstart article](https://learn.microsoft.com/azure/logic-apps/quickstart-create-deploy-azure-resource-manager-template).
