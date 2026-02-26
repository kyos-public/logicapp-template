<#
.SYNOPSIS
    Retrieves a user's UPN based on their employeeId.

.DESCRIPTION
    This runbook fetches a user's User Principal Name (UPN) from on-premise Active Directory
    using the unique employeeId attribute.

.PARAMETER EmployeeId
    The unique employee identifier.

.EXAMPLE
    Get-UserUPNByEmployeeId -EmployeeId "12345"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId
)

try {
    # Import Active Directory module
    Import-Module ActiveDirectory -ErrorAction Stop

    # Query user by employeeId
    $user = Get-ADUser -Filter "EmployeeId -eq '$EmployeeId'" -Properties UserPrincipalName, EmployeeId

    # Build JSON response
    $result = @{
        Success = $false
        EmployeeId = $EmployeeId
        UserPrincipalName = $null
        ErrorMessage = $null
    }

    if ($user) {
        $result.Success = $true
        $result.UserPrincipalName = $user.UserPrincipalName
    }
    else {
        $result.ErrorMessage = "No user found with employeeId: $EmployeeId"
    }

    # Output JSON for Logic App parsing
    $result | ConvertTo-Json -Compress
}
catch {
    # Output error as JSON
    @{
        Success = $false
        EmployeeId = $EmployeeId
        UserPrincipalName = $null
        ErrorMessage = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
