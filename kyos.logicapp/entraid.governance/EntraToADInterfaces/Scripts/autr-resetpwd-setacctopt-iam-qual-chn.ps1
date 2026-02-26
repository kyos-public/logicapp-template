<#
.SYNOPSIS
    Resets an Active Directory user's password and forces password change at next logon.

.DESCRIPTION
    This Azure Automation runbook resets a specified user's Active Directory password
    and sets the "User must change password at next logon" flag.

.PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user whose password will be reset.

.PARAMETER NewPassword
    The new password as a plain string that will be set for the user.

.NOTES
    Requires: ActiveDirectory PowerShell module
    Azure Automation Asset: AD credential with permissions to reset passwords
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,
    
    [Parameter(Mandatory = $true)]
    [string]$NewPassword
)

try {
    Write-Output "Starting password reset process for user: $UserPrincipalName"
    Write-Output "Running under gMSA authentication context"
    
    # Import Active Directory module
    Write-Output "Importing Active Directory module..."
    Import-Module ActiveDirectory -ErrorAction Stop
    
    # Get the AD user object using UPN
    Write-Output "Retrieving AD user object for: $UserPrincipalName"
    $ADUser = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -ErrorAction Stop
    
    if ($null -eq $ADUser) {
        throw "User not found with UserPrincipalName: $UserPrincipalName"
    }
    
    Write-Output "Found user: $($ADUser.SamAccountName) (Distinguished Name: $($ADUser.DistinguishedName))"
    
    # Convert plain text password to SecureString
    Write-Output "Converting password to secure string..."
    $SecurePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
    
    # Reset the user's password using SamAccountName
    Write-Output "Resetting password for user: $($ADUser.SamAccountName)"
    Set-ADAccountPassword -Identity $ADUser.SamAccountName `
                          -NewPassword $SecurePassword `
                          -Reset `
                          -ErrorAction Stop
    
    Write-Output "Password reset successful"
    
    # Set "Change password at next logon" flag
    Write-Output "Setting 'Change password at next logon' flag..."
    Set-ADUser -Identity $ADUser.SamAccountName `
               -ChangePasswordAtLogon $true `
               -ErrorAction Stop
    
    Write-Output "Successfully completed password reset for user: $UserPrincipalName"
    Write-Output "User will be required to change password at next logon"
    
    # Return success status
    $result = @{
        Status = "Success"
        User = $UserPrincipalName
        Message = "Password reset completed and change password at next logon flag set"
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    Write-Output "Result: $($result | ConvertTo-Json)"
    return $result
}
catch {
    Write-Error "Error occurred during password reset: $($_.Exception.Message)"
    Write-Error "Error details: $($_.Exception)"
    
    # Return error status
    $result = @{
        Status = "Failed"
        User = $UserPrincipalName
        Message = $_.Exception.Message
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    Write-Output "Result: $($result | ConvertTo-Json)"
    throw
}
