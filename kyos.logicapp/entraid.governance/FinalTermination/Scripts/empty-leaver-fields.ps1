<#
.SYNOPSIS
    Removes the manager and extensionAttribute7 attributes from an Active Directory user identified by employeeId.

.DESCRIPTION
    This Azure Automation runbook empties the "manager" and "extensionAttribute7" AD attributes for a user
    identified by their employeeId. The search is performed domain-wide, as employeeId
    is a unique attribute in Active Directory.

.PARAMETER EmployeeId
    The employeeId of the user whose manager and extensionAttribute7 attributes will be cleared.

.EXAMPLE
    Remove-UserManager.ps1 -EmployeeId "12345"

.NOTES
    Author: Azure Automation
    Date: 2026-02-03
    
    Prerequisites:
    - Azure Automation Account with Hybrid Runbook Worker
    - ActiveDirectory PowerShell module installed on Hybrid Worker
    - Run As account or managed identity with permissions to modify AD users
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId
)

# Import required modules
Import-Module ActiveDirectory -ErrorAction Stop

try {
    Write-Output "Starting runbook execution..."
    Write-Output "Employee ID: $EmployeeId"

    # Search for the user by employeeId across the entire domain
    Write-Output "Searching for user with employeeId: $EmployeeId"

    $user = Get-ADUser -Filter "employeeNumber -eq '$EmployeeId'" `
                       -Properties employeeId, manager, extensionAttribute7, DisplayName, DistinguishedName `
                       -ErrorAction Stop

    # Check if user was found
    if ($null -eq $user) {
        throw "No user found with employeeId '$EmployeeId'."
    }

    # Check if multiple users were found
    if ($user -is [array] -and $user.Count -gt 1) {
        Write-Warning "Multiple users found with employeeId '$EmployeeId':"
        foreach ($u in $user) {
            Write-Warning "  - $($u.DisplayName) ($($u.DistinguishedName))"
        }
        throw "Multiple users found with the same employeeId. Manual intervention required."
    }

    Write-Output "User found: $($user.DisplayName) ($($user.DistinguishedName))"

    # Check if manager attribute has a value
    if ([string]::IsNullOrWhiteSpace($user.manager)) {
        Write-Output "The manager attribute is already empty for this user. No action needed."
    }
    else {
        Write-Output "Current manager: $($user.manager)"
        
        # Clear the manager attribute
        Set-ADUser -Identity $user.DistinguishedName -Clear manager -ErrorAction Stop
        
        Write-Output "Successfully cleared the manager attribute for user: $($user.DisplayName)"
        
        # Verify the change
        $updatedUser = Get-ADUser -Identity $user.DistinguishedName -Properties manager
        
        if ([string]::IsNullOrWhiteSpace($updatedUser.manager)) {
            Write-Output "Verification successful: Manager attribute is now empty."
        }
        else {
            Write-Warning "Verification warning: Manager attribute still contains a value: $($updatedUser.manager)"
        }
    }

    # Check if extensionAttribute7 attribute has a value
    if ([string]::IsNullOrWhiteSpace($user.extensionAttribute7)) {
        Write-Output "The extensionAttribute7 attribute is already empty for this user. No action needed."
    }
    else {
        Write-Output "Current extensionAttribute7: $($user.extensionAttribute7)"

        # Clear the extensionAttribute7 attribute
        Set-ADUser -Identity $user.DistinguishedName -Clear extensionAttribute7 -ErrorAction Stop

        Write-Output "Successfully cleared the extensionAttribute7 attribute for user: $($user.DisplayName)"

        # Verify the change
        $updatedUser = Get-ADUser -Identity $user.DistinguishedName -Properties extensionAttribute7

        if ([string]::IsNullOrWhiteSpace($updatedUser.extensionAttribute7)) {
            Write-Output "Verification successful: extensionAttribute7 attribute is now empty."
        }
        else {
            Write-Warning "Verification warning: extensionAttribute7 attribute still contains a value: $($updatedUser.extensionAttribute7)"
        }
    }
    
    Write-Output "Runbook execution completed successfully."
}
catch {
    Write-Error "An error occurred during runbook execution: $_"
    Write-Error $_.Exception.Message
    Write-Error $_.ScriptStackTrace
    throw
}
