# PowerShell Script Documentation: MoveUserInDisabledOU.ps1

## Overview
This PowerShell script is designed to be used in Entra ID Governance workflows when a user is leaving the organization. It moves the specified user to a dedicated "Disabled Users" Organizational Unit (OU) in Active Directory and optionally disables the user account.

## Purpose
- **Primary Function**: Move departing users to a centralized disabled users OU
- **Secondary Function**: Disable the user account if not already disabled
- **Integration**: Designed for use with Azure Logic Apps and Entra ID Governance workflows
- **Environment**: Runs on on-premises servers with Active Directory access

## Parameters

### Required Parameters
- **`userPrincipalName`** (string): The UPN of the user to be moved (e.g., "john.doe@company.com")

### Optional Parameters
- **`disabledOU`** (string): The Distinguished Name of the target disabled users OU
  - Default: `"OU=Disabled Users,DC=domain,DC=com"`
  - Example: `"OU=Terminated Users,OU=Disabled,DC=contoso,DC=com"`

## Prerequisites

### Active Directory Environment
1. **Active Directory PowerShell Module**: Must be installed on the executing server
2. **Permissions**: The executing account must have:
   - Read permissions on user objects
   - Move permissions on user objects
   - Write permissions to the target disabled OU
   - Account disable permissions (if using account disabling feature)

### Organizational Unit Setup
1. Create a dedicated OU for disabled users (e.g., "OU=Disabled Users")
2. Ensure proper permissions are set on the OU
3. Consider implementing appropriate Group Policy settings for the disabled OU

## Usage Examples

### Basic Usage (with default OU)
```powershell
.\MoveUserInDisabledOU.ps1 -userPrincipalName "john.doe@company.com"
```

### With Custom Disabled OU
```powershell
.\MoveUserInDisabledOU.ps1 -userPrincipalName "john.doe@company.com" -disabledOU "OU=Terminated,OU=Users,DC=contoso,DC=com"
```

### From Logic App (JSON parameter)
```json
{
    "userPrincipalName": "john.doe@company.com",
    "disabledOU": "OU=Disabled Users,DC=company,DC=com"
}
```

## Output

The script returns a JSON object with the following structure:

```json
{
    "Success": true,
    "Message": "User successfully moved to disabled OU - Account disabled",
    "UserDN": "CN=John Doe,OU=Sales,DC=company,DC=com",
    "PreviousOU": "OU=Sales,DC=company,DC=com",
    "NewOU": "OU=Disabled Users,DC=company,DC=com",
    "Timestamp": "2024-08-18 14:30:25"
}
```

### Success Response Fields
- **Success**: Boolean indicating operation success
- **Message**: Human-readable status message
- **UserDN**: Original Distinguished Name of the user
- **PreviousOU**: The OU where the user was located before the move
- **NewOU**: The target disabled users OU
- **Timestamp**: When the operation was performed

### Error Response Example
```json
{
    "Success": false,
    "Message": "Error: User not found: invalid.user@company.com",
    "UserDN": "",
    "PreviousOU": "",
    "NewOU": "",
    "Timestamp": "2024-08-18 14:30:25"
}
```

## Features

### Smart Detection
- Checks if user is already in the disabled OU (prevents unnecessary moves)
- Verifies target OU exists before attempting the move
- Validates user existence before processing

### Account Management
- Automatically disables user accounts that are still enabled
- Skips disabling if account is already disabled
- Provides clear status messages for all operations

### Error Handling
- Comprehensive error handling with detailed error messages
- Graceful handling of missing users, OUs, or permission issues
- Returns structured JSON for easy integration with automation workflows

### Logging
- Detailed Write-Output statements for operational visibility
- Error details for troubleshooting
- Timestamp tracking for audit purposes

## Integration with Entra ID Governance

### Workflow Integration
This script is designed to be called as part of a larger user offboarding workflow:

1. **Trigger**: User marked for termination in Entra ID Governance
2. **Pre-requisites**: Other offboarding steps (license removal, group removal, etc.)
3. **This Script**: Move user to disabled OU and disable account
4. **Post-processing**: Additional cleanup or notification steps

### Logic App Integration
The script can be called from Azure Logic Apps using the "Run PowerShell Script" action:

```json
{
    "type": "PowerShell",
    "inputs": {
        "script": "path/to/MoveUserInDisabledOU.ps1",
        "parameters": {
            "userPrincipalName": "@{triggerBody()['userPrincipalName']}",
            "disabledOU": "OU=Disabled Users,DC=company,DC=com"
        }
    }
}
```

## Security Considerations

### Permissions
- Use a dedicated service account with minimal required permissions
- Regularly audit and review service account permissions
- Consider using Privileged Access Management (PAM) for sensitive operations

### Audit Trail
- All operations are logged with timestamps
- Consider implementing additional logging to Security Event Log
- Monitor for unauthorized use of the script

### Validation
- The script validates user existence before processing
- Target OU existence is verified before attempting moves
- Failed operations return detailed error information

## Troubleshooting

### Common Issues

1. **"User not found" Error**
   - Verify the userPrincipalName is correct
   - Check if user exists in Active Directory
   - Ensure the executing account has read permissions

2. **"Disabled OU not found" Error**
   - Verify the disabledOU parameter is correct
   - Check OU Distinguished Name syntax
   - Ensure OU exists and is accessible

3. **Permission Denied Errors**
   - Verify service account has move permissions
   - Check permissions on source and target OUs
   - Ensure account has disable user permissions

4. **Module Import Errors**
   - Verify Active Directory PowerShell module is installed
   - Check PowerShell execution policy
   - Ensure proper Windows features are enabled

### Best Practices

1. **Testing**: Always test the script in a non-production environment first
2. **Backup**: Consider backing up user objects before mass operations
3. **Monitoring**: Implement monitoring for script execution and failures
4. **Documentation**: Maintain documentation of your specific OU structure and naming conventions

## Version History

- **v1.0**: Initial version with basic move functionality and account disabling capability
