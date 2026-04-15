<#
.SYNOPSIS
    Generates unique UPN and display name for a batch of Entra ID (Azure AD) AdminC user creations.

.DESCRIPTION
    This runbook receives a Base64-encoded JSON payload containing an array of users
    (from ServiceNow via Azure Logic Apps) and generates unique UPNs and display names
    for each user. Intra-batch collision tracking ensures that two users processed in
    the same batch will never receive the same UPN.
    The entire batch fails if any single user encounters an error.

.PARAMETER PayloadBase64
    Base64-encoded JSON string. Once decoded, it must be a JSON array of objects,
    each containing at least "first_name", "last_name", and "u_correlation_id" properties.

.OUTPUTS
    JSON object keyed by u_correlation_id with userPrincipalName and displayName per user.

.EXAMPLE
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jsonArray))
    .\autr-compute-unique-entra-ext-iam-qual-chn.ps1 -PayloadBase64 $payload
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PayloadBase64
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
        Uses a single batched Graph query on the base pattern to minimise API round-trips.
        Also checks the intra-batch set of already-assigned UPNs.
    .PARAMETER AlreadyAssigned
        Hashtable of UPNs already assigned within the current batch (lowercase keys).
    .OUTPUTS
        Hashtable with UPN and ConflictIndex (0 if no conflict, >0 if conflict resolved)
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Domain,
        [hashtable]$AlreadyAssigned = @{}
    )

    # Normalize input - remove spaces and special characters, convert to lowercase
    $firstName = $FirstName.Trim() -replace '[^a-zA-Z]', ''
    $lastName  = $LastName.Trim()  -replace '[^a-zA-Z]', ''

    if ([string]::IsNullOrEmpty($firstName) -or [string]::IsNullOrEmpty($lastName)) {
        throw "First name and last name must contain at least one letter."
    }

    $firstPart = $firstName.ToLower().Substring(0, [Math]::Min(3, $firstName.Length))
    $lastPart  = $lastName.ToLower().Substring(0, [Math]::Min(3, $lastName.Length))
    $basePattern = $firstPart + $lastPart

    Write-Warning "Base pattern: $basePattern"

    # Fetch all existing UPNs that start with the base pattern in one API call
    # This avoids N round-trips when conflicts exist
    $filterPrefix = "$basePattern" + "a"
    $existingUpns = @{}
    try {
        $matches = Get-AzADUser -Filter "startsWith(userPrincipalName,'$filterPrefix')" -ErrorAction Stop
        foreach ($u in $matches) {
            $existingUpns[$u.UserPrincipalName.ToLower()] = $true
        }
        Write-Warning "Found $($existingUpns.Count) existing UPN(s) matching prefix '$filterPrefix'"
    } catch {
        Write-Warning "Batched UPN query failed, falling back to individual checks: $($_.Exception.Message)"
        # existingUpns stays empty - individual checks below will handle it
    }

    # Helper: checks both Entra and intra-batch
    function Test-UPNTaken {
        param([string]$CandidateUPN)
        if ($AlreadyAssigned.ContainsKey($CandidateUPN.ToLower())) { return $true }
        if ($existingUpns.ContainsKey($CandidateUPN.ToLower()))    { return $true }
        return $false
    }

    # Check base candidate first (no index)
    $upn = "$filterPrefix@$Domain"
    if (-not (Test-UPNTaken -CandidateUPN $upn)) {
        # Double-check with direct lookup only if the batch returned nothing (fallback path)
        if ($existingUpns.Count -eq 0) {
            $directCheck = $null
            try { $directCheck = Get-AzADUser -UserPrincipalName $upn -ErrorAction Stop } catch {}
            if ($null -eq $directCheck) {
                Write-Warning "UPN '$upn' is available (no conflict)"
                return @{ UPN = $upn; ConflictIndex = 0 }
            }
        } else {
            Write-Warning "UPN '$upn' is available (no conflict)"
            return @{ UPN = $upn; ConflictIndex = 0 }
        }
    }

    Write-Warning "UPN '$upn' already exists. Trying with index..."

    # Find the first available slot
    for ($counter = 1; $counter -lt 1000; $counter++) {
        $upn = "$basePattern$counter" + "a@$Domain"
        if (-not (Test-UPNTaken -CandidateUPN $upn)) {
            Write-Warning "UPN '$upn' is available (conflict index: $counter)"
            return @{ UPN = $upn; ConflictIndex = $counter }
        }
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

    # Decode Base64 payload
    Write-Warning "Decoding Base64 payload..."
    try {
        $jsonString = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PayloadBase64))
        $users = ($jsonString | ConvertFrom-Json).body
    } catch {
        throw "Failed to decode or parse Base64 payload: $($_.Exception.Message)"
    }

    if ($null -eq $users -or $users.Count -eq 0) {
        throw "Payload is empty or contains no users."
    }

    Write-Warning "Processing batch of $($users.Count) user(s) for AdminC accounts"

    # Get the UPN domain from Azure Automation variable
    $upnDomain = Get-AutomationVariable -Name "aut-var-upn-domain"

    if ([string]::IsNullOrEmpty($upnDomain)) {
        throw "aut-var-upn-domain automation variable is not set or is empty."
    }

    Write-Warning "UPN Domain: $upnDomain"

    # Intra-batch collision tracking
    $assignedUPNs = @{}  # lowercase UPN -> $true

    # Result mapping keyed by u_correlation_id
    $results = [ordered]@{}

    foreach ($user in $users) {
        $correlationId = $user.u_correlation_id
        $userFirstName = $user.first_name
        $userLastName  = $user.last_name

        if ([string]::IsNullOrEmpty($correlationId)) {
            throw "A user entry is missing the u_correlation_id field."
        }

        if ([string]::IsNullOrEmpty($userFirstName) -or [string]::IsNullOrEmpty($userLastName)) {
            throw "User '$correlationId' is missing first_name or last_name."
        }

        Write-Warning "Processing user '$correlationId': $userFirstName $userLastName"

        # Generate unique UPN (checking both Entra and intra-batch)
        $upnResult = Get-UniqueUPN -FirstName $userFirstName -LastName $userLastName `
            -Domain $upnDomain -AlreadyAssigned $assignedUPNs

        $userPrincipalName = $upnResult.UPN
        $conflictIndex = $upnResult.ConflictIndex

        # Track this UPN in the intra-batch set
        $assignedUPNs[$userPrincipalName.ToLower()] = $true

        Write-Warning "  -> UPN: $userPrincipalName (Conflict Index: $conflictIndex)"

        # Generate display name (with conflict index if applicable)
        $displayName = Get-DisplayName -FirstName $userFirstName -LastName $userLastName -ConflictIndex $conflictIndex

        Write-Warning "  -> Display Name: $displayName"

        # Add to results mapping
        $results[$correlationId] = [PSCustomObject]@{
            userPrincipalName = $userPrincipalName
            displayName       = $displayName
            status            = "Success"
        }
    }

    # Wrap with global status and timestamp
    $output = [PSCustomObject]@{
        status    = "Success"
        timestamp = (Get-Date).ToString("o")
        results   = $results
    }

    # Output as JSON for Logic Apps consumption
    $output | ConvertTo-Json -Depth 4 -Compress

} catch {
    # Error handling - return error in JSON format for Logic Apps
    $errorOutput = [PSCustomObject]@{
        status       = "Error"
        errorMessage = $_.Exception.Message
        timestamp    = (Get-Date).ToString("o")
        results      = $null
    }

    $errorOutput | ConvertTo-Json -Depth 4 -Compress

    # Exit with error code
    Write-Error $_.Exception.Message
    exit 1
}

#endregion
