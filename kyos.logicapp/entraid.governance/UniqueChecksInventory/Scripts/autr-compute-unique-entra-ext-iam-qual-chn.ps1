<#
.SYNOPSIS
    Generates unique UPN and display name for Entra ID (Azure AD) user creation.

.DESCRIPTION
    This runbook generates unique UPN for Entra ID user accounts
    based on first and last names. Optimized for repeated calls from Azure Logic Apps.

.PARAMETER FirstName
    The user's first name.

.PARAMETER LastName
    The user's last name.

.OUTPUTS
    JSON object with userPrincipalName and displayName properties.

.EXAMPLE
    .\New-UniqueEntraUPN.ps1 -FirstName "John" -LastName "Doe"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FirstName,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LastName
)

#region Functions

function Initialize-EntraModule {
    <#
    .SYNOPSIS
        Ensures Az.Resources module is loaded and Azure connection is established.
    #>
    if (-not (Get-Module -Name Az.Resources -ListAvailable)) {
        throw "Az.Resources module is not available. This runbook requires Az modules in Azure Automation."
    }
    
    if (-not (Get-Module -Name Az.Resources)) {
        Import-Module Az.Resources -ErrorAction Stop
    }
    
    if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
        throw "Az.Accounts module is not available. This runbook requires Az modules in Azure Automation."
    }
    
    if (-not (Get-Module -Name Az.Accounts)) {
        Import-Module Az.Accounts -ErrorAction Stop
    }
    
    # Connect to Azure using Service Principal or Managed Identity
    Write-Warning "Connecting to Azure..."
    try {
        # Try to get service principal credentials from automation variables
        $spnClientId = $null
        $spnClientSecret = $null
        $tenantId = $null
        
        try {
            $spnClientId = Get-AutomationVariable -Name "SPNClientId" -ErrorAction SilentlyContinue
            $spnClientSecret = Get-AutomationVariable -Name "SPNClientSecret" -ErrorAction SilentlyContinue
            $tenantId = Get-AutomationVariable -Name "TenantId" -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "SPN variables not found, will try managed identity"
        }
        
        # Use Service Principal if credentials are available
        if (-not [string]::IsNullOrEmpty($spnClientId) -and -not [string]::IsNullOrEmpty($spnClientSecret) -and -not [string]::IsNullOrEmpty($tenantId)) {
            Write-Warning "Authenticating using Service Principal with Client ID: $spnClientId"
            $securePassword = ConvertTo-SecureString $spnClientSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($spnClientId, $securePassword)
            Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId -ErrorAction Stop | Out-Null
            Write-Warning "Successfully connected to Azure using Service Principal"
        }
        # Fallback to Managed Identity
        else {
            Write-Warning "Service Principal credentials not found, trying Managed Identity..."
            
            # Try to get user-assigned managed identity client ID from automation variable
            $userAssignedIdentityClientId = $null
            try {
                $userAssignedIdentityClientId = Get-AutomationVariable -Name "ManagedIdentityClientId" -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "ManagedIdentityClientId variable not found, will try system-assigned identity"
            }
            
            if (-not [string]::IsNullOrEmpty($userAssignedIdentityClientId)) {
                Write-Warning "Using user-assigned managed identity with Client ID: $userAssignedIdentityClientId"
                Connect-AzAccount -Identity -AccountId $userAssignedIdentityClientId -ErrorAction Stop | Out-Null
            } else {
                Write-Warning "Using system-assigned managed identity"
                Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            }
            
            Write-Warning "Successfully connected to Azure using Managed Identity"
        }
        
        # Get current context to verify
        $context = Get-AzContext
        Write-Warning "Connected as: $($context.Account.Id) to tenant: $($context.Tenant.Id)"
        
        # Set the subscription context
        try {
            $subscriptionId = Get-AutomationVariable -Name "SubscriptionId" -ErrorAction SilentlyContinue
            
            if (-not [string]::IsNullOrEmpty($subscriptionId)) {
                Write-Warning "Setting Azure context to subscription: $subscriptionId"
                Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
                Write-Warning "Successfully set context to subscription: $subscriptionId"
            } else {
                Write-Warning "SubscriptionId variable not found, using default subscription from context"
            }
        } catch {
            Write-Warning "Failed to set subscription context: $($_.Exception.Message)"
            throw "Failed to set subscription context: $($_.Exception.Message)"
        }
    } catch {
        throw "Failed to connect to Azure: $($_.Exception.Message)"
    }
}

function Get-UniqueUPN {
    <#
    .SYNOPSIS
        Generates a unique User Principal Name.
    .DESCRIPTION
        Format: firstName[0,3] + lastName[0,3] + "a" + @domain
        If not unique, inserts index before "a" (1a, 2a, 3a, etc.)
        Example: John Smith with domain @contoso.com = johsmia@contoso.com
        Next conflict: johsmi1a@contoso.com, johsmi2a@contoso.com, etc.
    .OUTPUTS
        Hashtable with UPN and ConflictIndex (0 if no conflict, >0 if conflict resolved)
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Domain
    )
    
    # Normalize input - remove spaces and special characters, convert to lowercase
    $firstName = $FirstName.Trim() -replace '[^a-zA-Z]', ''
    $lastName = $LastName.Trim() -replace '[^a-zA-Z]', ''
    
    if ([string]::IsNullOrEmpty($firstName) -or [string]::IsNullOrEmpty($lastName)) {
        throw "First name and last name must contain at least one letter."
    }
    
    $firstNameLower = $firstName.ToLower()
    $lastNameLower = $lastName.ToLower()
    
    # Get first 3 characters (or less if name is shorter)
    $firstPart = if ($firstNameLower.Length -ge 3) { 
        $firstNameLower.Substring(0, 3) 
    } else { 
        $firstNameLower 
    }
    
    $lastPart = if ($lastNameLower.Length -ge 3) { 
        $lastNameLower.Substring(0, 3) 
    } else { 
        $lastNameLower 
    }
    
    # Base pattern: first3 + last3
    $basePattern = $firstPart + $lastPart
    
    Write-Warning "Base pattern: $basePattern"
    
    # Try base pattern with "a" suffix first
    $upnPrefix = $basePattern + "a"
    $upn = "$upnPrefix@$Domain"
    
    Write-Warning "Checking UPN: $upn"
    
    # Check if base UPN exists
    $existingUser = $null
    try {
        # Using Az.Resources cmdlet (native in Azure Automation)
        Write-Warning "Attempting Get-AzADUser -UserPrincipalName '$upn'..."
        $existingUser = Get-AzADUser -UserPrincipalName $upn -ErrorAction Stop
        Write-Warning "Get-AzADUser returned: $($existingUser -ne $null) (User object: $($existingUser.UserPrincipalName))"
    } catch {
        # Check if it's a "not found" error or a real error
        if ($_.Exception.Message -like "*does not exist*" -or $_.Exception.Message -like "*Cannot find*" -or $_.Exception.Message -like "*not found*") {
            Write-Warning "User not found (expected): $($_.Exception.Message)"
        } else {
            Write-Warning "ERROR checking UPN '$upn': $($_.Exception.Message)"
            Write-Warning "Error type: $($_.Exception.GetType().FullName)"
        }
    }
    
    if ($null -eq $existingUser) {
        Write-Warning "UPN '$upn' is available (no conflict)"
        return @{
            UPN = $upn
            ConflictIndex = 0
        }
    }
    
    Write-Warning "UPN '$upn' already exists (conflict detected). Trying with index..."
    
    # If not unique, append numbers before "a"
    $counter = 1
    
    while ($counter -lt 1000) {
        $upnPrefix = "$basePattern$counter" + "a"
        $upn = "$upnPrefix@$Domain"
        
        Write-Warning "Checking UPN: $upn"
        
        $existingUser = $null
        try {
            Write-Warning "Attempting Get-AzADUser -UserPrincipalName '$upn'..."
            $existingUser = Get-AzADUser -UserPrincipalName $upn -ErrorAction Stop
            Write-Warning "Get-AzADUser returned: $($existingUser -ne $null) (User object: $($existingUser.UserPrincipalName))"
        } catch {
            # Check if it's a "not found" error or a real error
            if ($_.Exception.Message -like "*does not exist*" -or $_.Exception.Message -like "*Cannot find*" -or $_.Exception.Message -like "*not found*") {
                Write-Warning "User not found (expected): $($_.Exception.Message)"
            } else {
                Write-Warning "ERROR checking UPN '$upn': $($_.Exception.Message)"
                Write-Warning "Error type: $($_.Exception.GetType().FullName)"
            }
        }
        
        if ($null -eq $existingUser) {
            Write-Warning "UPN '$upn' is available"
            return @{
                UPN = $upn
                ConflictIndex = $counter
            }
        }
        
        Write-Warning "UPN '$upn' already exists, trying next index..."
        $counter++
    }
    
    throw "Unable to generate unique UPN after 1000 attempts."
}

function Get-DisplayName {
    <#
    .SYNOPSIS
        Generates display name for the user.
    .DESCRIPTION
        Format: FirstName LASTNAME AdminC
        If conflict index provided, appends " {index}" at the end
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [int]$ConflictIndex = 0
    )
    
    # Normalize input - remove extra spaces but preserve capitalization for first name
    $firstName = $FirstName.Trim() -replace '\s+', ''
    $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
    
    $baseName = "$firstName $lastNameUpper AdminC"
    
    if ($ConflictIndex -gt 0) {
        return "$baseName $ConflictIndex"
    }
    
    return $baseName
}

#endregion

#region Main Script

try {
    # Initialize Az module
    Initialize-EntraModule
    
    Write-Warning "Script started for: $FirstName $LastName"
    
    # Get the UPN domain from Azure Automation variable
    $upnDomain = Get-AutomationVariable -Name "aut-var-upn-domain"
    
    if ([string]::IsNullOrEmpty($upnDomain)) {
        throw "aut-var-upn-domain automation variable is not set or is empty."
    }
    
    Write-Warning "UPN Domain: $upnDomain"
    
    # Generate unique UPN
    $upnResult = Get-UniqueUPN -FirstName $FirstName -LastName $LastName -Domain $upnDomain
    $userPrincipalName = $upnResult.UPN
    $conflictIndex = $upnResult.ConflictIndex
    
    Write-Warning "Generated UPN: $userPrincipalName (Conflict Index: $conflictIndex)"
    
    # Generate display name (with conflict index if applicable)
    $displayName = Get-DisplayName -FirstName $FirstName -LastName $LastName -ConflictIndex $conflictIndex
    
    Write-Warning "Generated Display Name: $displayName"
    
    # Prepare output for Azure Logic Apps (JSON format)
    $output = [PSCustomObject]@{
        userPrincipalName = $userPrincipalName
        displayName       = $displayName
        firstName         = $FirstName.Trim()
        lastName          = $LastName.Trim()
        status            = "Success"
        timestamp         = (Get-Date).ToString("o")
    }
    
    # Output as JSON for Logic Apps consumption
    $output | ConvertTo-Json -Compress
    
} catch {
    # Error handling - return error in JSON format for Logic Apps
    $errorOutput = [PSCustomObject]@{
        userPrincipalName = $null
        displayName       = $null
        firstName         = $FirstName
        lastName          = $LastName
        status            = "Error"
        errorMessage      = $_.Exception.Message
        timestamp         = (Get-Date).ToString("o")
    }
    
    $errorOutput | ConvertTo-Json -Compress
    
    # Exit with error code
    Write-Error $_.Exception.Message
    exit 1
}

#endregion
