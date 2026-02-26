<#
.SYNOPSIS
    Adds a user to Active Directory groups based on access package mapping.

.DESCRIPTION
    This runbook adds a user to groups mapped to an access package. It supports two types of groups:
    1. Parent Group: Uses AD group nesting - user is added to parent, inherits sub-group access
    2. Additional Groups: Systems incompatible with nesting - user is added directly to each group

.PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user to add to groups (e.g., user@domain.com).

.PARAMETER AccessPackageName
    The name of the access package (e.g., "Accounting", "IT", "Sales").

.PARAMETER Base64DepartmentMapping
    A base64-encoded JSON string that maps access package names to groups.
    Example JSON structure:
    {
        "Accounting": ["GRP_Department_Accounting", "GRP_Legacy_App1", "GRP_Legacy_App2"],
        "IT": ["GRP_Department_IT"]
    }

.PARAMETER MaxRetries
    Maximum number of retry attempts when adding a user to a group. Default is 3.

.PARAMETER RetryDelaySeconds
    Delay in seconds between retry attempts. Default is 2 seconds.

.EXAMPLE
    # Create the access-package mapping
    $mapping = @{
        "Accounting" = @("GRP_Department_Accounting", "GRP_Legacy_App1", "GRP_Legacy_App2")
        "IT" = @("GRP_Department_IT")
    } | ConvertTo-Json
    
    # Encode to base64
    $base64Mapping = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($mapping))
    
    # Run the script
    .\Add-UserToDepartmentGroups.ps1 `
        -UserPrincipalName "jdoe@contoso.com" `
        -AccessPackageName "Accounting" `
        -Base64DepartmentMapping $base64Mapping

.NOTES
    Author: Generated Script
    Date: 2026-01-28
    Version: 4.0
    Requires: Active Directory PowerShell Module
    
    All groups are listed flat under each access package name.
    User is added to all groups in the list.
#>
#


[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "User Principal Name (e.g., user@domain.com)")]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $true, HelpMessage = "Employee Id (e.g., jdoe)")]
    [ValidateNotNullOrEmpty()]
    [string]$EmployeeId,

    [Parameter(Mandatory = $false, HelpMessage = "Employee type (e.g., EXT-ADMC)")]
    [string]$EmployeeType,

    [Parameter(Mandatory = $true, HelpMessage = "Access package name (e.g., Accounting)")]
    [ValidateNotNullOrEmpty()]
    [string]$AccessPackageName,

    [Parameter(Mandatory = $true, HelpMessage = "Base64-encoded JSON mapping of access packages to parent groups")]
    [ValidateNotNullOrEmpty()]
    [string]$Base64DepartmentMapping,

    [Parameter(Mandatory = $false, HelpMessage = "Maximum number of retry attempts")]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false, HelpMessage = "Delay between retry attempts in seconds")]
    [ValidateRange(1, 30)]
    [int]$RetryDelaySeconds = 2
)

#region Functions

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Verbose')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'Info'    { "[INFO]   " }
        'Warning' { "[WARN]   " }
        'Error'   { "[ERROR]  " }
        'Success' { "[OK]     " }
        'Verbose' { "[VERBOSE]" }
    }
    
    $logMessage = "$timestamp $prefix $Message"
    
    # Azure Automation runbooks: Use Write-Output for all streams to ensure visibility in job logs
    switch ($Level) {
        'Warning' { 
            Write-Output $logMessage
            Write-Warning $Message 
        }
        'Error'   { 
            Write-Output $logMessage
            Write-Error $Message -ErrorAction Continue
        }
        'Verbose' {
            Write-Verbose $logMessage
        }
        default   { 
            Write-Output $logMessage 
        }
    }
}

function Get-AccessPackageMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base64String
    )
    
    try {
        $jsonString = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64String))
        
        $mapping = $jsonString | ConvertFrom-Json
        return $mapping
    }
    catch {
        throw "Failed to decode access package mapping: $_"
    }
}

function Add-UserToGroupWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADGroup]$Group,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = 2
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            if ($attempt -gt 1) {
                Write-LogMessage "Retry attempt $attempt of $MaxAttempts for group '$($Group.Name)'..." -Level Info
                Start-Sleep -Seconds $DelaySeconds
            }
            
            Add-ADGroupMember -Identity $Group -Members $User -ErrorAction Stop
            Write-LogMessage "Successfully added user to group '$($Group.Name)' (attempt $attempt)" -Level Success
            return $true
        }
        catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts) {
                Write-LogMessage "Attempt $attempt failed for group '$($Group.Name)': $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    Write-LogMessage "Failed to add user to group '$($Group.Name)' after $MaxAttempts attempts: $lastError" -Level Error
    return $false
}

#endregion

#region Main Script

$ErrorActionPreference = 'Stop'

try {
    Write-LogMessage "========================================"
    Write-LogMessage "Starting Access Package Assignment"
    Write-LogMessage "========================================"
    Write-LogMessage "User UPN: $UserPrincipalName"
    Write-LogMessage "Access Package: $AccessPackageName"
    Write-LogMessage "Max Retries: $MaxRetries"
    Write-LogMessage "Retry Delay: $RetryDelaySeconds seconds"
    
    # Get SearchBase from automation variable
    Write-LogMessage "Retrieving SearchBase from automation variable..."
    try {
        $searchBase = Get-AutomationVariable -Name 'SearchBaseOU' -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($searchBase)) {
            throw "SearchBaseOU automation variable is empty"
        }
        Write-LogMessage "SearchBase OU: $searchBase" -Level Success
    }
    catch {
        throw "Failed to retrieve SearchBaseOU automation variable: $_"
    }
    
    # Import Active Directory module
    Write-LogMessage "Checking for Active Directory module..."
    
    # Check if module is available
    $adModule = Get-Module -Name ActiveDirectory -ListAvailable
    if (-not $adModule) {
        throw "Active Directory module is not installed. Please install RSAT-AD-PowerShell feature or RSAT tools."
    }
    Write-LogMessage "Active Directory module found: Version $($adModule.Version)" -Level Success
    
    # Import the module
    Write-LogMessage "Importing Active Directory module..."
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-LogMessage "Active Directory module imported successfully" -Level Success
    }
    catch {
        throw "Failed to import Active Directory module: $_"
    }
    
    # Verify critical cmdlets are available
    $requiredCmdlets = @('Get-ADUser', 'Get-ADGroup', 'Get-ADGroupMember', 'Add-ADGroupMember')
    foreach ($cmdlet in $requiredCmdlets) {
        if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
            throw "Required cmdlet '$cmdlet' is not available. Active Directory module may not be properly installed."
        }
    }
    Write-LogMessage "All required AD cmdlets are available" -Level Success
    
    # Decode and parse the access package mapping
    Write-LogMessage "Decoding access package mapping..."
    $accessPackageMapping = Get-AccessPackageMapping -Base64String $Base64DepartmentMapping
    
    # Validate access package exists in mapping
    $availablePackages = $accessPackageMapping.PSObject.Properties.Name
    if (-not $availablePackages.Contains($AccessPackageName)) {
        throw "Access package '$AccessPackageName' not found in mapping. Available packages: $($availablePackages -join ', ')"
    }
    
    # Get groups for the access package
    $groupNames = $accessPackageMapping.$AccessPackageName
    
    if (-not $groupNames -or $groupNames.Count -eq 0) {
        throw "No groups mapped for access package '$AccessPackageName'"
    }
    
    Write-LogMessage "Groups for '$AccessPackageName': $($groupNames.Count) group(s)"
    foreach ($groupName in $groupNames) {
        Write-LogMessage "  - $groupName"
    }
    
# Verify user exists based on employeeId and employeeType
Write-LogMessage "Verifying user exists in Active Directory..."

# Determine search strategy based on employeeType
if ($employeeType -like "*ADMC*") {
    # For ADMC users, search by employeeId with "-a" suffix
    $searchEmployeeId = "$employeeId-a"
    Write-LogMessage "Searching for ADMC user with employeeId: $searchEmployeeId"
    
    $user = Get-ADUser -Filter "employeeId -eq '$searchEmployeeId'" -SearchBase $searchBase -ErrorAction Stop
    if ($null -eq $user) {
        throw "User with employeeId '$searchEmployeeId' not found in Active Directory"
    }
}
elseif ([string]::IsNullOrEmpty($employeeType) -or $employeeType -like "*STD*") {
    # For EXT-STD users or INT users, search by UPN
    Write-LogMessage "Searching for user with UPN: $UserPrincipalName"
    
    $user = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -SearchBase $searchBase -ErrorAction Stop
    if ($null -eq $user) {
        throw "User with UPN '$UserPrincipalName' not found in Active Directory"
    }
}
else {
    throw "Unsupported employeeType: $employeeType"
}

Write-LogMessage "User found: $($user.Name) [$($user.SamAccountName)]" -Level Success
Write-LogMessage "Distinguished Name: $($user.DistinguishedName)"
    
    # Process all groups
    Write-LogMessage "========================================"
    Write-LogMessage "Processing Groups"
    Write-LogMessage "========================================"
    
    $successCount = 0
    $alreadyMemberCount = 0
    $failureCount = 0
    
    foreach ($groupName in $groupNames) {
        Write-LogMessage "Processing: $groupName"
        
        try {
            # Verify group exists
            $group = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $searchBase -ErrorAction Stop
            if ($null -eq $group) {
                Write-LogMessage "Group '$groupName' not found in Active Directory" -Level Warning
                $failureCount++
                continue
            }
            
            # Check if user is already a member
            $members = Get-ADGroupMember -Identity $group -ErrorAction Stop
            $isMember = $members | Where-Object { $_.DistinguishedName -eq $user.DistinguishedName }
            
            if ($isMember) {
                Write-LogMessage "User is already a member of '$groupName' - Skipping"
                $alreadyMemberCount++
            }
            else {
                # Add user to group
                $result = Add-UserToGroupWithRetry -User $user -Group $group -MaxAttempts $MaxRetries -DelaySeconds $RetryDelaySeconds
                
                if ($result) {
                    $successCount++
                }
                else {
                    $failureCount++
                }
            }
        }
        catch {
            Write-LogMessage "Failed to process group '$groupName': $_" -Level Error
            $failureCount++
        }
    }
    
    # Summary
    Write-LogMessage "========================================"
    Write-LogMessage "Execution Summary"
    Write-LogMessage "========================================"
    Write-LogMessage "Access Package: $AccessPackageName"
    Write-LogMessage "User: $($user.Name)"
    Write-LogMessage "Groups:"
    Write-LogMessage "  Total: $($groupNames.Count)"
    Write-LogMessage "  Successfully Added: $successCount"
    Write-LogMessage "  Already Member: $alreadyMemberCount"
    Write-LogMessage "  Failed: $failureCount"
    Write-LogMessage "========================================"
    
    # Determine overall result
    if ($failureCount -eq 0) {
        Write-LogMessage "Runbook completed successfully!" -Level Success
        exit 0
    }
    else {
        Write-LogMessage "Runbook completed with failures" -Level Error
        exit 1
    }
}
catch {
    Write-LogMessage "========================================" -Level Error
    Write-LogMessage "Runbook execution failed!" -Level Error
    Write-LogMessage "Error: $_" -Level Error
    Write-LogMessage "========================================" -Level Error
    throw
}

#endregion
