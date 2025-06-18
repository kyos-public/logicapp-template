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

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkyos-public%2Flogicapp-template%2Fmain%2Fkyos.logicapp%2Fentraid.governance%2FSendPasswordToIT%2FSendPasswordToIT.json)

## Prerequisites

Before deploying this template to a new tenant, ensure you have:

- **Azure subscription** with Logic Apps service enabled
- **Managed Identity permissions** configured for Microsoft Graph API access
- **Email connector permissions** (Office 365 Outlook or other email service)
- **Required API permissions** granted in the target tenant:
  - `User.Read.All` (Microsoft Graph)
  - `Mail.Send` (Microsoft Graph)

## Connection Configuration

This template uses managed identity for secure authentication. After deployment, you may need to:

1. **Configure Managed Identity**: Ensure the Logic App's system-assigned managed identity has appropriate permissions
2. **Update API Connections**: Verify all API connections are properly authenticated in the target tenant
3. **Grant Admin Consent**: Some Graph API permissions require admin consent in the target tenant

Azure Logic Apps is a cloud service that automates the execution of your business processes. You can create a workflow by using a visual designer to arrange prebuilt components into the sequence that you need. When you save your workflow, the designer sends the workflow's definition to the Azure Logic Apps execution engine. When the conditions for the workflow's trigger are met, the engine launches the workflow and manages the compute resources that the workflow needs to run. If you're new to Azure Logic Apps, see [What is Azure Logic Apps?](https://learn.microsoft.com/azure/logic-apps/logic-apps-overview).

This quickstart template creates a basic workflow to send pw by email to IT after joiner workflow.

## Post-Deployment Steps

1. Navigate to the deployed Logic App in the Azure portal
2. Go to **Identity** section and note the Object ID of the system-assigned managed identity
3. In **Azure Active Directory > Enterprise Applications**, find the managed identity and assign required permissions
4. Test the workflow to ensure all connections are working properly

## Troubleshooting Connection Issues

If you encounter connection errors:

- **403 Forbidden**: Check if managed identity has required Graph API permissions
- **401 Unauthorized**: Verify API connections are authenticated for the target tenant
- **Connection not found**: Recreate API connections in the Logic App designer

For information about using this template, see [Create Azure Resource Manager templates for Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-create-deploy-template). To learn more about how to deploy the template, see the [quickstart article](https://learn.microsoft.com/azure/logic-apps/quickstart-create-deploy-azure-resource-manager-template).
