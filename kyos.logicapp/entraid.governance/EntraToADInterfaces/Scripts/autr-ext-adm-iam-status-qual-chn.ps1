<#
.SYNOPSIS
    Enable or disable an Active Directory user account.

.DESCRIPTION
    This runbook enables or disables a specified AD user account based on the action parameter.

.PARAMETER EmployeeId
    The EmployeeID of the user to modify.

.PARAMETER Action
    The action to perform: "Enable" or "Disable"

.EXAMPLE
    .\Enable-DisableADUser.ps1 -EmployeeId "12345" -Action "Disable"
    
.EXAMPLE
    .\Enable-DisableADUser.ps1 -EmployeeId "67890" -Action "Enable"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("Enable", "Disable")]
    [string]$Action
)

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Verbose "Active Directory module loaded successfully." -Verbose
}
catch {
    Write-Error "Failed to load Active Directory module: $_"
    throw
}

# Get SearchBase OU from Azure Automation variable
try {
    $SearchBaseOU = Get-AutomationVariable -Name 'aut-var-searchbaseou'
    Write-Verbose "Using SearchBase OU: $SearchBaseOU" -Verbose
}
catch {
    Write-Error "Failed to retrieve aut-var-searchbaseou automation variable: $_"
    throw
}

# Find user by EmployeeID within the specified OU
try {
    $ADUser = Get-ADUser -Filter "EmployeeID -eq '$EmployeeId'" -SearchBase $SearchBaseOU -Properties EmployeeID -ErrorAction Stop
    
    if (-not $ADUser) {
        Write-Error "No user found with EmployeeID: $EmployeeId in OU: $SearchBaseOU"
        throw "User not found"
    }
    
    if ($ADUser.Count -gt 1) {
        Write-Warning "Multiple users found with EmployeeID: $EmployeeId in OU: $SearchBaseOU. Using first match."
        $ADUser = $ADUser[0]
    }
    
    Write-Verbose "Found user: $($ADUser.Name) ($($ADUser.SamAccountName)) - EmployeeID: $EmployeeId in OU: $SearchBaseOU" -Verbose
}
catch {
    Write-Error "Failed to find user with EmployeeID '$EmployeeId' in OU '$SearchBaseOU': $_"
    throw
}

# Perform the action
try {
    switch ($Action) {
        "Enable" {
            Enable-ADAccount -Identity $ADUser.SamAccountName -ErrorAction Stop
            Write-Verbose "User account '$($ADUser.SamAccountName)' (EmployeeID: $EmployeeId) has been enabled." -Verbose
        }
        "Disable" {
            Disable-ADAccount -Identity $ADUser.SamAccountName -ErrorAction Stop
            Write-Verbose "User account '$($ADUser.SamAccountName)' (EmployeeID: $EmployeeId) has been disabled." -Verbose
        }
    }
    
    # Verify the change
    $UpdatedUser = Get-ADUser -Identity $ADUser.SamAccountName -Properties Enabled, EmployeeID
    Write-Verbose "Current account status - Enabled: $($UpdatedUser.Enabled)" -Verbose
    
    # Output result object for Azure Automation
    $Result = [PSCustomObject]@{
        EmployeeID = $EmployeeId
        UserName = $ADUser.SamAccountName
        DisplayName = $ADUser.Name
        Action = $Action
        Success = $true
        Enabled = $UpdatedUser.Enabled
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    Write-Output $Result
}
catch {
    Write-Error "Failed to $Action account for EmployeeID '$EmployeeId': $_"
    throw
}
