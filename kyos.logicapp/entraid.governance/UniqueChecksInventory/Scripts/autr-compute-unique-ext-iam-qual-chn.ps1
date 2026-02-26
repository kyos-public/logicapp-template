<#
.SYNOPSIS
    Generates unique SAM account name and cn name for AD user creation.

.DESCRIPTION
    This runbook generates unique identifiers for Active Directory user accounts
    based on first and last names. Optimized for repeated calls from Azure Logic Apps.

.PARAMETER FirstName
    The user's first name.

.PARAMETER LastName
    The user's last name.

.PARAMETER AccountType
    The type of account to create. Valid values: ADM (admin account) or STD (standard account).
    Default is ADM.

.OUTPUTS
    JSON object with samAccountName, employeeNumber, and CN properties.

.EXAMPLE
    .\New-UniqueADAccountName.ps1 -FirstName "John" -LastName "Doe" -AccountType "ADM"
    
.EXAMPLE
    .\New-UniqueADAccountName.ps1 -FirstName "John" -LastName "Doe" -AccountType "STD"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FirstName,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LastName,
    
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
        ADM accounts: adm + firstName[index] + lastName[0:1]
        STD accounts: firstName[index] + lastName
        If not unique, uses next letter from firstName (index 1, 2, 3...), then lastName.
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$SearchBase,
        [string]$AccountType = "ADM"
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
        # ADM account logic: adm + firstName[index] + lastName[0:1]
        $basePattern = "adm"
        $lastNamePart = if ($lastNameLower.Length -ge 2) { 
            $lastNameLower.Substring(0, 2) 
        } else { 
            $lastNameLower 
        }
        
        # Try each letter position in firstName (0, 1, 2, 3...)
        $firstNameIndex = 0
        while ($firstNameIndex -lt $firstNameLower.Length) {
            $firstNamePart = $firstNameLower.Substring(0,$firstNameIndex+1)
            $samAccountName = $firstNamePart + $lastNameLower
            
            # Ensure SAM account name doesn't exceed 16 characters (employeeNumber limit)
            if ($samAccountName.Length -gt 16) {
                $samAccountName = $samAccountName.Substring(0, 16)
            }
            
            # Check if this SAM account name exists
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
        
        # If we've exhausted firstName letters, use lastName letters
        $lastNameIndex = 0
        while ($lastNameIndex -lt $lastNameLower.Length) {
            $lastNameLetter = $lastNameLower[$lastNameIndex]
            
            # Use last firstName letter + current lastName letter + rest of lastName
            $lastFirstNameLetter = $firstNameLower[$firstNameLower.Length - 1]
            
            # Build: adm + lastNameLetter + remaining lastName chars (up to 2 total from lastName)
            if ($lastNameLower.Length -ge 2) {
                $remainingLastName = $lastNameLower.Substring(1, 1)
                $samAccountName = $basePattern + $lastNameLetter + $remainingLastName
            } else {
                $samAccountName = $basePattern + $lastNameLetter + $remainingLastName
            }
            
            # Ensure SAM account name doesn't exceed 16 characters
            if ($samAccountName.Length -gt 16) {
                $samAccountName = $samAccountName.Substring(0, 16)
            }
            
            # Check if this SAM account name exists
            $existingUser = $null
            try {
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -SearchBase $SearchBase -ErrorAction SilentlyContinue
            } catch {
                # Ignore errors, treat as not found
            }
            
            if ($null -eq $existingUser) {
                return $samAccountName
            }
            
            $lastNameIndex++
        }
        
        # If still not unique, append numbers
        $baseSam = $basePattern + $firstNameLower[0] + $lastNamePart
        if ($baseSam.Length -gt 14) {
            $baseSam = $baseSam.Substring(0, 14)
        }
        
        $counter = 1
        while ($counter -lt 100) {
            $samAccountName = "$baseSam$counter"
            
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
        
        throw "Unable to generate unique SAM account name after 100 attempts."
        
    } else {
        # STD account logic: firstName[index] + lastName
        # Try each letter position in firstName (0, 1, 2, 3...)
        $firstNameIndex = 0
        while ($firstNameIndex -lt $firstNameLower.Length) {
            $firstNameLetter = $firstNameLower[$firstNameIndex]
            $samAccountName = $firstNameLetter + $lastNameLower
            
            # Ensure SAM account name doesn't exceed 16 characters (employeeNumber limit)
            if ($samAccountName.Length -gt 16) {
                $samAccountName = $samAccountName.Substring(0, 16)
            }
            
            # Check if this SAM account name exists
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
        
        throw "Unable to generate unique SAM account name after 100 attempts."
    }
}

function Get-UniqueCN {
    <#
    .SYNOPSIS
        Generates a unique cn name (CN).
    .DESCRIPTION
        ADM accounts: Admin FirstName LASTNAME
        STD accounts: FirstName LastName
        If not unique, appends index number based on count of exact homonyms.
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$SearchBase,
        [string]$AccountType = "ADM"
    )
    
    # Normalize input - remove extra spaces but preserve capitalization for display
    $firstName = $FirstName.Trim() -replace '\s+', ''
    
    if ($AccountType -eq "ADM") {
        $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
        # Base cn name: Admin FirstName LASTNAME
        $baseCN = "Admin $firstName $lastNameUpper"
    } else {
        $lastName = $LastName.Trim() -replace '\s+', ''
        # Base cn name: FirstName LastName
        $baseCN = "$firstName $lastName"
    }
    
    # Check if CN is unique
    $existingUsers = $null
    try {
        # Search for users with CN starting with the base pattern
        if ($AccountType -eq "ADM") {
            $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
            $searchFilter = "CN -like 'Admin $firstName $lastNameUpper*'"
        } else {
            $lastName = $LastName.Trim() -replace '\s+', ''
            $searchFilter = "CN -like '$firstName $lastName*'"
        }
        $existingUsers = @(Get-ADUser -Filter $searchFilter -SearchBase $SearchBase -Properties CN -ErrorAction SilentlyContinue)
    } catch {
        # If search fails, assume no conflicts
        return $baseCN
    }
    
    if ($null -eq $existingUsers -or $existingUsers.Count -eq 0) {
        return $baseCN
    }
    
    # Count exact homonyms (same base name)
    $homonymCount = 0
    if ($AccountType -eq "ADM") {
        $lastNameUpper = ($LastName.Trim() -replace '\s+', '').ToUpper()
        $exactPattern = "^Admin $firstName $lastNameUpper( \d+)?$"
    } else {
        $lastName = $LastName.Trim() -replace '\s+', ''
        $exactPattern = "^$firstName $lastName( \d+)?$"
    }
    
    foreach ($user in $existingUsers) {
        if ($user.CN -match $exactPattern) {
            $homonymCount++
        }
    }
    
    if ($homonymCount -eq 0) {
        return $baseCN
    }
    
    # Append the count as index
    return "$baseCN $homonymCount"
}

#endregion

#region Main Script

try {
    # Initialize AD module
    Initialize-ADModule
    
    # Get the SearchBase OU from Azure Automation variable
    $searchBaseOU = Get-AutomationVariable -Name "SearchBaseOU"
    
    if ([string]::IsNullOrEmpty($searchBaseOU)) {
        throw "SearchBaseOU automation variable is not set or is empty."
    }
    
    # Generate unique SAM account name
    $samAccountName = Get-UniqueSamAccountName -FirstName $FirstName -LastName $LastName -SearchBase $searchBaseOU -AccountType $AccountType
    
    # Generate unique cn name
    $CN = Get-UniqueCN -FirstName $FirstName -LastName $LastName -SearchBase $searchBaseOU -AccountType $AccountType
    
    # Prepare output for Azure Logic Apps (JSON format)
    $output = [PSCustomObject]@{
        samAccountName = $samAccountName
        employeeNumber = $samAccountName
        cn  = $CN
        firstName      = $FirstName.Trim()
        lastName       = $LastName.Trim()
        accountType    = $AccountType
        status         = "Success"
        timestamp      = (Get-Date).ToString("o")
    }
    
    # Output as JSON for Logic Apps consumption
    $output | ConvertTo-Json -Compress
    
} catch {
    # Error handling - return error in JSON format for Logic Apps
    $errorOutput = [PSCustomObject]@{
        samAccountName = $null
        employeeNumber = $null
        cn  = $null
        firstName      = $FirstName
        lastName       = $LastName
        status         = "Error"
        errorMessage   = $_.Exception.Message
        timestamp      = (Get-Date).ToString("o")
    }
    
    $errorOutput | ConvertTo-Json -Compress
    
    # Exit with error code
    Write-Error $_.Exception.Message
    exit 1
}

#endregion
