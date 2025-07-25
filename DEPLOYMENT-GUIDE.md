# Logic App Template Update Summary

## ✅ All Templates Updated Successfully!

All Logic App ARM templates have been updated to support cross-tenant deployment and implement standardized resource tagging.

## 🏷️ Standardized Tags Applied

All resources (Logic Apps and API connections) now include these standardized tags:

```json
{
  "WorkloadName": "SharedTools",
  "ApplicationName": "IAM",
  "DataClassification": "Low",
  "BusinessCriticality": "Low",
  "Owner": "Kyos",
  "Environment": "Prod",
  "CreatedBy": "Terraform",
  "OperationTeam": "Infra"
}
```

### Resource Types Tagged

- ✅ **Microsoft.Logic/workflows** (Logic Apps)
- ✅ **Microsoft.Web/connections** (API connections)

## 📁 Template-Specific Updates

### 1. AddUserInOnpremGroup

- ✅ Parameters updated to include location, automationAccountName, automationResourceGroupName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Hardcoded resource group names replaced with parameters
- ✅ Connection resources added to template
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated

### 2. SendPasswordToIT

- ✅ Parameters updated to include location, automationAccountName, automationResourceGroupName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Hardcoded resource group names replaced with parameters
- ✅ Connection resources added to template
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated

### 3. MoveUserInDisabledOU

- ✅ Parameters updated to include location, automationAccountName, automationResourceGroupName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Hardcoded resource group names replaced with parameters
- ✅ Connection resources added to template (azureautomation, acsemail)
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated
- ✅ Managed Identity authentication preserved
- ✅ **Fixed automation account path reference in Logic App definition**

### 4. SendPasswordSMS

- ✅ Parameters updated to include location, automationAccountName, automationResourceGroupName, onpremAutomationAccountName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Hardcoded resource group names replaced with parameters
- ✅ Connection resources added to template (azureautomation, azurecommunicationservicessms, acsemail)
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated
- ✅ Multiple automation accounts supported

### 5. OrderLicenses

- ✅ Parameters updated to include location, keyVaultName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Connection resources added to template (keyvault)
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated
- ✅ Managed Identity authentication preserved
- ✅ **Key Vault connection configured for managed identity support**

### 6. EntraIDProvisioning

- ✅ Parameters updated to include location, keyVaultName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Connection resources added to template (keyvault)
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated
- ✅ Managed Identity authentication preserved
- ✅ **Key Vault connection configured for managed identity support**

### 6. EntraIDProvisioning

- ✅ Parameters updated to include location, keyVaultName
- ✅ Hardcoded subscription ID replaced with subscription().subscriptionId
- ✅ Connection resources added to template (keyvault)
- ✅ Dependencies added to Logic App resource
- ✅ Parameter file updated
- ✅ Managed Identity authentication preserved
- ✅ **Key Vault connection configured for managed identity support**

### 7. FinalTermination

- ✅ Parameters updated to include location
- ✅ Hardcoded location replaced with parameter
- ✅ Parameter file updated
- ✅ No external connections (uses only Managed Identity)

## Key Changes Made for Cross-Tenant Deployment

1. **Parameterized Hardcoded Values**:
   - Subscription ID: `subscription().subscriptionId`
   - Location: `parameters('location')` with default `[resourceGroup().location]`
   - Automation Account Name: `parameters('automationAccountName')`
   - Resource Group Name: `parameters('automationResourceGroupName')`
   - Key Vault Name: `parameters('keyVaultName')` (for Key Vault templates)

2. **Connection Resources**:
   - Added connection resources to each template that requires them
   - Updated connection references to use dynamic resource IDs
   - Added dependencies to ensure proper deployment order

3. **Template Functions**:
   - Used `subscriptionResourceId()` for managed API references
   - Used `resourceId()` for connection references
   - Used `resourceGroup().location` for default location

4. **Parameter Files**:
   - Removed hardcoded external connection IDs
   - Added new parameters with sensible defaults
   - Updated schema version to 2019-04-01

## Connection Types by Template

- **AddUserInOnpremGroup**: azurefile, azureautomation
- **SendPasswordToIT**: azureautomation, acsemail
- **MoveUserInDisabledOU**: azureautomation, acsemail
- **SendPasswordSMS**: azureautomation, azurecommunicationservicessms, acsemail
- **OrderLicenses**: keyvault
- **EntraIDProvisioning**: keyvault
- **FinalTermination**: None (Managed Identity only)

## Post-Deployment Configuration Required

After deploying these templates to a new tenant, you'll need to:

1. **Configure API Connections**:
   - Navigate to each connection in the Azure portal
   - Provide authentication credentials
   - Test the connections

2. **Update Automation Account References**:
   - Ensure the automation account exists in the target tenant
   - Update runbook names if different
   - Configure automation account permissions

3. **Configure Key Vault Access**:
   - Grant Logic App managed identity permissions to Key Vault
   - Ensure secrets exist in the target Key Vault

4. **Configure Managed Identity**:
   - Assign appropriate permissions to the Logic App managed identity
   - Grant Graph API permissions for Entra ID operations

5. **Test Workflows**:
   - Run test executions to verify all connections work
   - Update any tenant-specific configurations (email addresses, etc.)

## Benefits of These Changes

- **✅ Cross-Tenant Deployment**: Templates can now be deployed to any tenant without modification
- **✅ No Pre-existing Connections**: Connections are created as part of the deployment
- **✅ Location Flexibility**: Templates adapt to the target resource group location
- **✅ Standardized Tagging**: All resources follow consistent tagging strategy for governance
- **✅ Resource Tracking**: Tags enable better cost management and resource organization
- **✅ Compliance Ready**: Tags support organizational compliance and operational requirements
- **✅ Parameterized Configuration**: Easy to customize for different environments
- **✅ Proper Dependencies**: Resources are deployed in the correct order
- **✅ Managed Identity Support**: Preserved for secure authentication where applicable

## Deployment Command Examples

```bash
# Deploy a template to a new tenant
az deployment group create \
  --resource-group "your-resource-group" \
  --template-file "AddUserInOnpremGroup.json" \
  --parameters "AddUserInOnpremGroup.parameters.json" \
  --parameters automationAccountName="your-automation-account" \
              automationResourceGroupName="your-automation-rg"

# Deploy with custom location
az deployment group create \
  --resource-group "your-resource-group" \
  --template-file "OrderLicenses.json" \
  --parameters "OrderLicenses.parameters.json" \
  --parameters location="eastus" \
              keyVaultName="your-keyvault"
```

## 🔧 Troubleshooting

### Key Vault Managed Identity Connection Issues

**Error 1**: `The workflow connection parameter 'keyvault' is not valid. The API connection 'keyvault' is not configured to support managed identity.`

**Error 2**: `The API connection 'keyvault-connection' has invalid inputs for the managed identity. 'ParameterValues' property should be null or empty when the parameter value type is set to 'Alternative'.`

**Solution**: The Key Vault connection resources in `EntraIDProvisioning` and `OrderLicenses` templates have been updated with proper managed identity configuration:

```json
{
    "properties": {
        "displayName": "Key Vault Connection",
        "api": {
            "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'keyvault')]"
        },
        "parameterValueType": "Alternative",
        "alternativeParameterValues": {
            "vaultName": "[parameters('keyVaultName')]"
        }
    }
}
```

**Key Points**:

- When using `"parameterValueType": "Alternative"`, the `"parameterValues"` property must be omitted
- Only `"alternativeParameterValues"` should contain the Key Vault name
- This configuration allows the Logic App to authenticate to Key Vault using its system-assigned managed identity

### Template Parameter Reference Error (MoveUserInDisabledOU)

**Error**: `The template parameter 'automationAccounts___encodeURIComponent__onprem_powershell_execution____externalid' is not found.`

**Solution**: The MoveUserInDisabledOU template had **multiple** leftover parameter references from the original export. Fixed automation account path references in both Logic App actions:

**Action 1 - Create_job**:

```json
// ❌ BEFORE
"path": "[concat(parameters('automationAccounts___encodeURIComponent__onprem_powershell_execution____externalid'), '/jobs')]"

// ✅ AFTER
"path": "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', parameters('automationResourceGroupName'), '/providers/Microsoft.Automation/automationAccounts/', parameters('automationAccountName'), '/jobs')]"
```

**Action 2 - Get_status_of_job**:

```json
// ❌ BEFORE  
"path": "[concat(parameters('automationAccounts___encodeURIComponent__onprem_powershell_execution____externalid'), '/jobs/@{encodeURIComponent(body(''Create_job'')?[''properties'']?[''jobId''])}')]"

// ✅ AFTER
"path": "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', parameters('automationResourceGroupName'), '/providers/Microsoft.Automation/automationAccounts/', parameters('automationAccountName'), '/jobs/@{encodeURIComponent(body(''Create_job'')?[''properties'']?[''jobId''])}')]"
```

Both references now use proper ARM template functions and parameterized values.

### Azure Automation Managed Identity Connection Error (MoveUserInDisabledOU)

**Error 1**: `The workflow connection parameter 'azureautomation' is not valid. The API connection 'azureautomation' is not configured to support managed identity.`

**Error 2**: `Parameter 'AutomationAccountName' is not allowed on the connection since it was not defined as a connection parameter when the API was registered.`

**Solution**: The Azure Automation connection configuration for managed identity authentication required specific setup. The final working configuration:

```json
// ❌ BEFORE - Missing managed identity configuration
"properties": {
    "displayName": "Azure Automation Connection",
    "api": {
        "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azureautomation')]"
    },
    "parameterValues": {}
}

// ❌ INTERMEDIATE - Invalid parameter
"properties": {
    "displayName": "Azure Automation Connection",
    "api": {
        "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azureautomation')]"
    },
    "parameterValueType": "Alternative",
    "alternativeParameterValues": {
        "AutomationAccountName": "[parameters('automationAccountName')]"
    }
}

// ✅ FINAL - Correct managed identity configuration
"properties": {
    "displayName": "Azure Automation Connection",
    "api": {
        "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azureautomation')]"
    },
    "parameterValueType": "Alternative",
    "alternativeParameterValues": {}
}
```

**Key Points**:

- For Azure Automation managed identity connections, use `"parameterValueType": "Alternative"`
- The `"alternativeParameterValues"` should be an empty object `{}`
- Do not specify automation account details in the connection - the Logic App references them directly in the action paths
- The automation account is referenced in the Logic App action paths using ARM template functions

All templates are now ready for cross-tenant deployment! 🎉
