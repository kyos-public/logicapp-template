param (
    [Parameter(Mandatory=$true)]
    [string]$userPrincipalName,

    [Parameter(Mandatory=$false)]
    [string]$disabledOU = "OU=Disabled Users,DC=domain,DC=com"
)

# Import Active Directory module
Import-Module ActiveDirectory -ErrorAction Stop

# Initialize result variables
$result = @{
    Success = $false
    Message = ""
    UserDN = ""
    PreviousOU = ""
    NewOU = ""
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

try {
    # Resolve user account
    Write-Output "Searching for user: $userPrincipalName"
    $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" -Properties DistinguishedName, Enabled -ErrorAction Stop
    
    if ($null -eq $user) {
        throw "User not found: $userPrincipalName"
    }

    Write-Output "User found: $($user.SamAccountName) - DN: $($user.DistinguishedName)"
    $result.UserDN = $user.DistinguishedName
    $result.PreviousOU = ($user.DistinguishedName -split ',',2)[1]

    # Check if user is already in the disabled OU
    if ($user.DistinguishedName -like "*$disabledOU*") {
        $result.Success = $true
        $result.Message = "User is already in the disabled OU: $disabledOU"
        $result.NewOU = $disabledOU
        Write-Output $result.Message
    }
    else {
        # Verify that the disabled OU exists
        try {
            Get-ADOrganizationalUnit -Identity $disabledOU -ErrorAction Stop | Out-Null
            Write-Output "Target OU verified: $disabledOU"
        }
        catch {
            throw "Disabled OU not found or not accessible: $disabledOU"
        }

        # Move user to disabled OU
        Write-Output "Moving user to disabled OU: $disabledOU"
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU -ErrorAction Stop
        
        # Verify the move was successful
        $movedUser = Get-ADUser -Identity $user.SamAccountName -Properties DistinguishedName -ErrorAction Stop
        if ($movedUser.DistinguishedName -like "*$disabledOU*") {
            $result.Success = $true
            $result.Message = "User successfully moved to disabled OU"
            $result.NewOU = $disabledOU
            Write-Output "SUCCESS: User $userPrincipalName moved from '$($result.PreviousOU)' to '$disabledOU'"
        }
        else {
            throw "Move operation appeared to succeed but user is not in expected OU"
        }
    }

    # Optional: Disable the user account if not already disabled
    if ($user.Enabled -eq $true) {
        Write-Output "Disabling user account: $userPrincipalName"
        Disable-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
        $result.Message += " - Account disabled"
        Write-Output "User account disabled successfully"
    }
    else {
        Write-Output "User account is already disabled"
        $result.Message += " - Account was already disabled"
    }
}
catch {
    $result.Success = $false
    $result.Message = "Error: $($_.Exception.Message)"
    Write-Error "FAILED: $($_.Exception.Message)"
    Write-Error "Full error details: $($_.Exception.ToString())"
}

# Return results as JSON for Logic App consumption
$result | ConvertTo-Json -Depth 3