<#
.SYNOPSIS
    Fast PowerShell runbook to fetch all employeeIDs from a given OU in Active Directory.

.DESCRIPTION
    This runbook queries Active Directory and retrieves all employeeIDs from a specified 
    Organizational Unit (OU). Optimized for performance and reliability in PowerShell 5.1 
    runbook runtime environments.

.PARAMETER OrganizationalUnit
    The Distinguished Name (DN) of the OU to query.
    Example: "OU=Users,OU=Company,DC=domain,DC=com"

.PARAMETER IncludeSubOUs
    Switch to include accounts from sub-OUs. Default is $true.

.EXAMPLE
    .\Get-ADAccountsInOU.ps1 -OrganizationalUnit "OU=Users,DC=contoso,DC=com"

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Requires: ActiveDirectory Module
    Runtime: PowerShell 5.1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OrganizationalUnit,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSubOUs = $true
)

#region Error Handling
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] [$Level] $Message"
}
#endregion

try {
    #region Import Active Directory Module
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "ActiveDirectory module is not available. Please ensure RSAT tools are installed."
    }
    
    Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false -WarningAction SilentlyContinue
    #endregion
    
    #region Build Search Parameters
    $searchParams = @{
        SearchBase = $OrganizationalUnit
        Filter = '*'
        Properties = 'employeeID', 'userPrincipalName', 'employeeType'
        ErrorAction = 'Stop'
    }
    
    # Determine search scope
    if ($IncludeSubOUs) {
        $searchParams.SearchScope = 'Subtree'
    } else {
        $searchParams.SearchScope = 'OneLevel'
    }
    #endregion
    
    #region Query Active Directory
    $startTime = Get-Date
    
    # Use optimized LDAP filter and minimal properties for maximum performance
    # Filter out users without employeeID set
    $users = Get-ADUser @searchParams | 
        Where-Object { $_.employeeID }
    
    $employeeIDs = $users | Select-Object -ExpandProperty employeeID
    
    # Create mapping array between employeeID and userPrincipalName
    $employeeMapping = @()
    foreach ($user in $users) {
        $employeeMapping += [PSCustomObject]@{
            EmployeeID = $user.employeeID
            UserPrincipalName = $user.userPrincipalName
            EmployeeType = $user.employeeType
        }
    }
    
    $duration = (Get-Date) - $startTime
    #endregion
    
    #region Results
    if ($employeeIDs) {
        $employeeIDCount = ($employeeIDs | Measure-Object).Count
        
        # Create JSON-serializable output for Logic App consumption
        $result = [PSCustomObject]@{
            Success = $true
            OU = $OrganizationalUnit
            EmployeeIDCount = $employeeIDCount
            EmployeeIDs = @($employeeIDs)  # Ensure array format
            EmployeeMapping = @($employeeMapping)  # Array of objects mapping employeeID to userPrincipalName
            QueryDurationSeconds = [math]::Round($duration.TotalSeconds, 2)
            Timestamp = (Get-Date).ToString("o")  # ISO 8601 format
        }
        
        # Output as JSON for Logic App parsing
        $jsonOutput = $result | ConvertTo-Json -Depth 10 -Compress 
        Write-Output $jsonOutput
        
        return $result
    } else {
        # Return structured error/empty result for Logic App
        $result = [PSCustomObject]@{
            Success = $true
            OU = $OrganizationalUnit
            EmployeeIDCount = 0
            EmployeeIDs = @()
            QueryDurationSeconds = [math]::Round($duration.TotalSeconds, 2)
            Timestamp = (Get-Date).ToString("o")
        }
        
        $jsonOutput = $result | ConvertTo-Json -Depth 10 -Compress
        Write-Output $jsonOutput
        
        return $result
    }
    #endregion
    
} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    # Return error as JSON for Logic App
    $errorResult = [PSCustomObject]@{
        Success = $false
        ErrorType = "ADIdentityNotFound"
        ErrorMessage = "The specified OU does not exist: $OrganizationalUnit"
        OU = $OrganizationalUnit
        Timestamp = (Get-Date).ToString("o")
    }
    Write-Output ($errorResult | ConvertTo-Json -Compress)
    throw
} catch {
    # Return error as JSON for Logic App
    $errorResult = [PSCustomObject]@{
        Success = $false
        ErrorType = $_.Exception.GetType().Name
        ErrorMessage = $_.Exception.Message
        OU = $OrganizationalUnit
        Timestamp = (Get-Date).ToString("o")
    }
    Write-Output ($errorResult | ConvertTo-Json -Compress)
    throw
}
