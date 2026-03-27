<#
.SYNOPSIS
    Generates unique SAM account names and CN names for a batch of AD user creations.

.DESCRIPTION
    This runbook receives a Base64-encoded JSON payload containing an array of users
    (from ServiceNow via Azure Logic Apps) and generates unique SAM account names and
    CN names for each user. Intra-batch collision tracking ensures that two users
    processed in the same batch will never receive the same identifiers.
    The entire batch fails if any single user encounters an error.

.PARAMETER PayloadBase64
    Base64-encoded JSON string. Once decoded, it must be a JSON array of objects,
    each containing at least "first_name", "last_name", and "u_correlation_id" properties.

.PARAMETER AccountType
    The type of account to create. Valid values: ADM (admin account) or STD (standard account).
    Default is ADM.

.OUTPUTS
    JSON object keyed by u_correlation_id with samAccountName, employeeNumber, and cn per user.

.EXAMPLE
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jsonArray))
    .\autr-compute-unique-ext-iam-qual-chn.ps1 -PayloadBase64 $payload -AccountType "ADM"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PayloadBase64,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ADM", "STD")]
    [string]$AccountType = "ADM"
)


#region Functions

function Initialize-ADModule {
    <#
    .SYNOPSIS
        Ensures AD module is loaded and available.
    #>
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "ActiveDirectory module is not installed. Please install RSAT tools."
    }

    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
}

function Get-UniqueSamAccountName {
    <#
    .SYNOPSIS
        Generates a unique SAM account name.
    .DESCRIPTION
        ADM accounts: adm + firstName[index] + lastName[0:2]  (single letter from firstName)
            Example: George MAYE -> admgma, admema, admoma, ...
        STD accounts: firstName[index] + lastName
            Example: George MAYE -> gmaye, emaye, omaye, ...
        If not unique (in AD or in the intra-batch set), moves to next firstName letter.
        After exhausting firstName, falls back to numeric suffix.
    .PARAMETER AlreadyAssigned
        Hashtable of SAM account names already assigned within the current batch (lowercase keys).
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$SearchBase,
        [string]$AccountType = "ADM",
        [hashtable]$AlreadyAssigned = @{}
    )

    # Normalize input - remove spaces and special characters, convert to lowercase
    $firstName = $FirstName.Trim() -replace '[^a-zA-Z]', ''
    $lastName = $LastName.Trim() -replace '[^a-zA-Z]', ''

    if ([string]::IsNullOrEmpty($firstName) -or [string]::IsNullOrEmpty($lastName)) {
        throw "First name and last name must contain at least one letter."
    }

    $firstNameLower = $firstName.ToLower()
    $lastNameLower = $lastName.ToLower()

    if ($AccountType -eq "ADM") {
        # ADM account logic: adm + firstName[index] (single char) + lastName[0:2]
        $basePattern = "adm"
        $lastNamePart = if ($lastNameLower.Length -ge 2) {
            $lastNameLower.Substring(0, 2)
        } else {
            $lastNameLower
        }

        # Try each letter position in firstName (0, 1, 2, 3...)
        $firstNameIndex = 0
        while ($firstNameIndex -lt $firstNameLower.Length) {
            $firstNameLetter = $firstNameLower[$firstNameIndex]
            $samAccountName = $basePattern + $firstNameLetter + $lastNamePart

            # Ensure SAM account name doesn't exceed 16 characters
            if ($samAccountName.Length -gt 16) {
                $samAccountName = $samAccountName.Substring(0, 16)
            }

            # Check intra-batch collision first
            if ($AlreadyAssigned.ContainsKey($samAccountName)) {
                $firstNameIndex++
                continue
            }

            # Check if this SAM account name exists in AD
            $existingUser = $null
            try {
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -SearchBase $SearchBase -ErrorAction SilentlyContinue
            } catch {
                # Ignore errors, treat as not found
            }

            if ($null -eq $existingUser) {
                return $samAccountName
            }

            $firstNameIndex++
        }

        # If still not unique, append numbers
        $baseSam = $basePattern + $firstNameLower[0] + $lastNamePart
        if ($baseSam.Length -gt 14) {
            $baseSam = $baseSam.Substring(0, 14)
        }

        $counter = 1
        while ($counter -lt 100) {
            $samAccountName = "$baseSam$counter"

            if ($AlreadyAssigned.ContainsKey($samAccountName)) {
                $counter++
                continue
            }

            $existingUser = $null
            try {
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -SearchBase $SearchBase -ErrorAction SilentlyContinue
            } catch {
                # Ignore errors, treat as not found
            }

            if ($null -eq $existingUser) {
                return $samAccountName
            }

            $counter++
        }

        throw "Unable to generate unique SAM account name after exhausting all attempts."

    } else {
        # STD account logic: firstName[index] + lastName
        # Try each letter position in firstName (0, 1, 2, 3...)
        $firstNameIndex = 0
        while ($firstNameIndex -lt $firstNameLower.Length) {
            $firstNameLetter = $firstNameLower[$firstNameIndex]
            $samAccountName = $firstNameLetter + $lastNameLower

            # Ensure SAM account name doesn't exceed 16 characters
            if ($samAccountName.Length -gt 16) {
                $samAccountName = $samAccountName.Substring(0, 16)
            }

            # Check intra-batch collision first
            if ($AlreadyAssigned.ContainsKey($samAccountName)) {
                $firstNameIndex++
                continue
            }

            # Check if this SAM account name exists in AD
            $existingUser = $null
            try {
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -SearchBase $SearchBase -ErrorAction SilentlyContinue
            } catch {
                # Ignore errors, treat as not found
            }

            if ($null -eq $existingUser) {
                return $samAccountName
            }

            $firstNameIndex++
        }

        # If still not unique, append numbers
        $baseSam = $firstNameLower[0] + $lastNameLower
        if ($baseSam.Length -gt 14) {
            $baseSam = $baseSam.Substring(0, 14)
        }

        $counter = 1
        while ($counter -lt 100) {
            $samAccountName = "$baseSam$counter"

            if ($AlreadyAssigned.ContainsKey($samAccountName)) {
                $counter++
                continue
            }

            $existingUser = $null
            try {
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -SearchBase $SearchBase -ErrorAction SilentlyContinue
            } catch {
                # Ignore errors, treat as not found
            }

            if ($null -eq $existingUser) {
                return $samAccountName
            }

            $counter++
        }

        throw "Unable to generate unique SAM account name after exhausting all attempts."
    }
}

function Get-UniqueCN {
    <#
    .SYNOPSIS
        Generates a unique CN name.
    .DESCRIPTION
        ADM accounts: Admin FirstName LASTNAME
        STD accounts: FirstName LastName
        If not unique, appends index number based on count of exact homonyms
        (both in AD and in the intra-batch set).
    .PARAMETER AlreadyAssignedCNs
        Hashtable of CN names already assigned within the current batch (lowercase keys).
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$SearchBase,
        [string]$AccountType = "ADM",
        [hashtable]$AlreadyAssignedCNs = @{}
    )

    # Normalize input - remove extra spaces but preserve capitalization for display
    $firstName = $FirstName.Trim() -replace '\s+', ''

    if ($AccountType -eq "ADM") {
        $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
        $baseCN = "Admin $firstName $lastNameUpper"
    } else {
        $lastName = $LastName.Trim() -replace '\s+', ''
        $baseCN = "$firstName $lastName"
    }

    # Count existing homonyms in AD
    $existingUsers = $null
    try {
        if ($AccountType -eq "ADM") {
            $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
            $searchFilter = "CN -like 'Admin $firstName $lastNameUpper*'"
        } else {
            $lastName = $LastName.Trim() -replace '\s+', ''
            $searchFilter = "CN -like '$firstName $lastName*'"
        }
        $existingUsers = @(Get-ADUser -Filter $searchFilter -SearchBase $SearchBase -Properties CN -ErrorAction SilentlyContinue)
    } catch {
        $existingUsers = @()
    }

    # Build the exact match pattern
    if ($AccountType -eq "ADM") {
        $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
        $exactPattern = "^Admin $firstName $lastNameUpper( \d+)?$"
    } else {
        $lastName = $LastName.Trim() -replace '\s+', ''
        $exactPattern = "^$firstName $lastName( \d+)?$"
    }

    # Count AD homonyms
    $homonymCount = 0
    foreach ($user in $existingUsers) {
        if ($user.CN -match $exactPattern) {
            $homonymCount++
        }
    }

    # Count intra-batch homonyms
    $batchPattern = "^" + [regex]::Escape($baseCN) + "( \d+)?$"
    foreach ($assignedCN in $AlreadyAssignedCNs.Keys) {
        if ($assignedCN -match $batchPattern) {
            $homonymCount++
        }
    }

    if ($homonymCount -eq 0) {
        return $baseCN
    }

    return "$baseCN $homonymCount"
}

#endregion

#region Main Script

try {
    # Initialize AD module
    Initialize-ADModule

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

    Write-Warning "Processing batch of $($users.Count) user(s) with AccountType=$AccountType"

    # Get the SearchBase OU from Azure Automation variable
    $searchBaseOU = Get-AutomationVariable -Name "aut-var-searchbaseou"

    if ([string]::IsNullOrEmpty($searchBaseOU)) {
        throw "aut-var-searchbaseou automation variable is not set or is empty."
    }

    # Intra-batch collision tracking
    $assignedSAMs = @{}   # lowercase SAM -> $true
    $assignedCNs  = @{}   # lowercase CN  -> $true

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

        Write-Warning "Processing user '$correlationId': $userFirstName $userLastName ($AccountType)"

        # Generate unique SAM account name (checking both AD and intra-batch)
        $samAccountName = Get-UniqueSamAccountName -FirstName $userFirstName -LastName $userLastName `
            -SearchBase $searchBaseOU -AccountType $AccountType -AlreadyAssigned $assignedSAMs

        # Track this SAM in the intra-batch set
        $assignedSAMs[$samAccountName] = $true

        # Generate unique CN (checking both AD and intra-batch)
        $cn = Get-UniqueCN -FirstName $userFirstName -LastName $userLastName `
            -SearchBase $searchBaseOU -AccountType $AccountType -AlreadyAssignedCNs $assignedCNs

        # Track this CN in the intra-batch set (lowercase for case-insensitive matching)
        $assignedCNs[$cn.ToLower()] = $true

        Write-Warning "  -> SAM: $samAccountName | CN: $cn"

        # Add to results mapping
        $results[$correlationId] = [PSCustomObject]@{
            samAccountName = $samAccountName
            employeeNumber = $samAccountName
            cn             = $cn
            accountType    = $AccountType
            status         = "Success"
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
