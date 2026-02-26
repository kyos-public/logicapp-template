<#
.SYNOPSIS
    Azure Automation Runbook - Update employeeLeaveDateTime in on-prem AD via extensionAttribute6.

.DESCRIPTION
    Called from a Logic App via the Azure Automation connector ("Create job" action).
    Receives a user's employeeId and sets the leave date portion of
    extensionAttribute6 to today's date.

    extensionAttribute6 format: yyyy-MM-dd;yyyy-MM-dd
                                 ^hireDate   ^leaveDate

    This script only updates the second part (leaveDate).

.NOTES
    Requires:
      - Hybrid Runbook Worker with AD connectivity
      - ActiveDirectory PowerShell module on the worker
      - Run As account with permission to modify user attributes in AD
#>


param (
    [Parameter(Mandatory = $true)]
    [string]$employeeId,          # e.g. "12345", "12345-s", "12345-a"

    [Parameter(Mandatory = $false)]
    [string]$userPrincipalName    # for logging purposes
)

Write-Output "Processing user: $userPrincipalName (employeeId=$employeeId)"

# ---------------------------------------------------------------------------
# 2. Find the AD user by employeeID
# ---------------------------------------------------------------------------
Import-Module ActiveDirectory

$adUser = Get-ADUser -Filter "employeeID -eq '$employeeId'" `
    -Properties extensionAttribute6, employeeID, SamAccountName

if (-not $adUser) {
    Write-Warning "No AD user found with employeeID='$employeeId'. Exiting."
    return
}

if (@($adUser).Count -gt 1) {
    Write-Warning "Multiple AD users found with employeeID='$employeeId'. Processing first match."
    $adUser = $adUser[0]
}

Write-Output "Found AD user: $($adUser.SamAccountName) (DN: $($adUser.DistinguishedName))"

# ---------------------------------------------------------------------------
# 3. Read and parse extensionAttribute6  (hireDate;leaveDate)
# ---------------------------------------------------------------------------
$extAttr6 = $adUser.extensionAttribute6

if ([string]::IsNullOrWhiteSpace($extAttr6)) {
    Write-Warning "extensionAttribute6 is empty for $($adUser.SamAccountName). Cannot parse hire date. Setting to ';yyyy-MM-dd'."
    $hireDate = ""
}
else {
    $parts = $extAttr6 -split ";"

    if ($parts.Count -ge 1) {
        $hireDate = $parts[0].Trim()
    }
    else {
        $hireDate = ""
    }

    # Log current values
    $currentLeaveDate = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "(not set)" }
    Write-Output "Current extensionAttribute6: hireDate=$hireDate, leaveDate=$currentLeaveDate"
}

# ---------------------------------------------------------------------------
# 4. Build the new value with today's date as the leave date
# ---------------------------------------------------------------------------
$today = (Get-Date).ToString("yyyy-MM-dd")
$newExtAttr6 = "$hireDate;$today"

Write-Output "Setting extensionAttribute6 to: $newExtAttr6"

# ---------------------------------------------------------------------------
# 5. Update the AD user
# ---------------------------------------------------------------------------
try {
    Set-ADUser -Identity $adUser.DistinguishedName -Replace @{
        extensionAttribute6 = $newExtAttr6
    }
    Write-Output "Successfully updated extensionAttribute6 for $($adUser.SamAccountName)."
}
catch {
    Write-Error "Failed to update AD user $($adUser.SamAccountName): $_"
    throw
}

# ---------------------------------------------------------------------------
# 6. Optional: force an Entra Connect delta sync
# ---------------------------------------------------------------------------
<#
    Uncomment the following if the Hybrid Runbook Worker is on the Entra Connect
    server and you want to trigger an immediate delta sync instead of waiting
    for the next 30-min cycle.

    Import-Module ADSync
    Start-ADSyncSyncCycle -PolicyType Delta
    Write-Output "Delta sync triggered."
#>

Write-Output "Done. The new leaveDate will appear in Entra ID after the next Entra Connect sync cycle."