# Runs in Azure Automation with a User-Assigned Managed Identity.
# Runtime: Windows PowerShell 5.1
# Required setup (one-time, outside this script):
#   - Attach the User-Assigned Managed Identity to the Automation Account
#   - Assign the identity the Entra role: Teams Communications Administrator (permanent, not PIM-eligible)
#   - Import modules in Automation Account (PowerShell 5.1 compatible versions):
#       * MicrosoftTeams >= 5.8.1 (minimum for -Identity support with *-Cs cmdlets)

param(
    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("set", "unset")]
    [string]$Action,

    # Required when Action = "set". E.164 format: +<countrycode><number> (e.g. +41791234567)
    [Parameter(Mandatory = $false)]
    [string]$PhoneNumber
)

# --- Import required modules ---

Import-Module MicrosoftTeams

# --- Auth: Connect using Managed Identity ---

$uaiId = Get-AutomationVariable -Name "aut-var-prod-uai-id"
Write-Host "Authenticating via User-Assigned Managed Identity..." -ForegroundColor Cyan
Connect-MicrosoftTeams -Identity -AccountId $uaiId
Write-Host "Authentication successful." -ForegroundColor Green

# ============================================================
# ACTION: SET — configure phone number and routing in Teams
# ============================================================
if ($Action -eq "set") {

    if (-not $PhoneNumber) {
        Write-Error "Parameter -PhoneNumber is required when Action is 'set'."
        exit 1
    }

    # Normalize to E.164: strip all non-digits, then prepend + (and country code if missing)
    $digitsOnly = $PhoneNumber -replace "[^\d]", ""
    if ($PhoneNumber -match "^\+") {
        $e164Phone = "+$digitsOnly"
    } else {
        $e164Phone = "+41$digitsOnly"   # <-- adjust country code if needed
        Write-Host "Normalized to E.164: $e164Phone" -ForegroundColor Yellow
    }

    Write-Host "Phone number to assign: $e164Phone" -ForegroundColor Green

    # --- Step 2: Assign the phone number in Teams ---

    Write-Host "Defining phone number..." -ForegroundColor Cyan
    try {
        Set-CsPhoneNumberAssignment `
            -Identity $UserPrincipalName `
            -PhoneNumber $e164Phone `
            -PhoneNumberType DirectRouting
        Write-Host "Phone number assigned: $e164Phone" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to assign phone number: $_"
        exit 1
    }

    # --- Step 3: Enable Enterprise Voice ---

    Write-Host "Enabling Enterprise Voice..." -ForegroundColor Cyan
    try {
        Set-CsPhoneNumberAssignment `
            -Identity $UserPrincipalName `
            -EnterpriseVoiceEnabled $true
        Write-Host "Enterprise Voice enabled." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to enable Enterprise Voice: $_"
        exit 1
    }

    # --- Step 4: Assign Online Voice Routing Policy ---

    Write-Host "Defining Online Voice Routing Policy..." -ForegroundColor Cyan
    try {
        Grant-CsOnlineVoiceRoutingPolicy `
            -Identity $UserPrincipalName `
            -PolicyName "CH-HQ-Online-International-Premium-Adult"
        Write-Host "Voice Routing Policy assigned." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to assign Voice Routing Policy: $_"
        exit 1
    }

    # --- Step 5: Assign Tenant Dial Plan ---

    Write-Host "Defining Tenant Dial Plan..." -ForegroundColor Cyan
    try {
        Grant-CsTenantDialPlan `
            -Identity $UserPrincipalName `
            -PolicyName "CH-HQ-Online"
        Write-Host "Tenant Dial Plan assigned." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to assign Tenant Dial Plan: $_"
        exit 1
    }

    # --- Step 6: Assign Teams Audio Conferencing Policy ---

    Write-Host "Defining Teams Audio Conferencing Policy..." -ForegroundColor Cyan
    try {
        Grant-CsTeamsAudioConferencingPolicy `
            -Identity $UserPrincipalName `
            -PolicyName "Conf Policy CH FR"
        Write-Host "Audio Conferencing Policy assigned." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to assign Audio Conferencing Policy: $_"
        exit 1
    }
}

# ============================================================
# ACTION: UNSET — free the phone number and remove routing
# Note: Entra phone number is NOT read here — at offboarding time,
#       the ServiceNow → AD Connect → Entra sync may not have run yet.
#       The number to release is read directly from Teams.
# ============================================================
elseif ($Action -eq "unset") {

    # Retrieve the current Teams state to find the assigned number
    $teamsUser = Get-CsOnlineUser -Identity $UserPrincipalName
    $assignedNumber = $teamsUser.LineUri -replace "^tel:", ""

    if (-not $assignedNumber) {
        Write-Warning "No phone number is currently assigned to '$UserPrincipalName' in Teams. Continuing to clean up policies."
    }

    # --- Step 2: Remove the phone number assignment ---

    if ($assignedNumber) {
        Write-Host "Removing phone number $assignedNumber..." -ForegroundColor Cyan
        try {
            Remove-CsPhoneNumberAssignment `
                -Identity $UserPrincipalName `
                -PhoneNumber $assignedNumber `
                -PhoneNumberType DirectRouting
            Write-Host "Phone number removed." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove phone number: $_"
            exit 1
        }
    }

    # --- Step 3: Disable Enterprise Voice ---

    Write-Host "Disabling Enterprise Voice..." -ForegroundColor Cyan
    try {
        Set-CsPhoneNumberAssignment `
            -Identity $UserPrincipalName `
            -EnterpriseVoiceEnabled $false
        Write-Host "Enterprise Voice disabled." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to disable Enterprise Voice: $_"
        exit 1
    }

    # --- Step 4: Remove Online Voice Routing Policy ---

    Write-Host "Removing Online Voice Routing Policy..." -ForegroundColor Cyan
    try {
        Grant-CsOnlineVoiceRoutingPolicy `
            -Identity $UserPrincipalName `
            -PolicyName $null
        Write-Host "Voice Routing Policy removed." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove Voice Routing Policy: $_"
        exit 1
    }

    # --- Step 5: Remove Tenant Dial Plan ---

    Write-Host "Removing Tenant Dial Plan..." -ForegroundColor Cyan
    try {
        Grant-CsTenantDialPlan `
            -Identity $UserPrincipalName `
            -PolicyName $null
        Write-Host "Tenant Dial Plan removed." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove Tenant Dial Plan: $_"
        exit 1
    }

    # --- Step 6: Remove Teams Audio Conferencing Policy ---

    Write-Host "Removing Teams Audio Conferencing Policy..." -ForegroundColor Cyan
    try {
        Grant-CsTeamsAudioConferencingPolicy `
            -Identity $UserPrincipalName `
            -PolicyName $null
        Write-Host "Audio Conferencing Policy removed." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove Audio Conferencing Policy: $_"
        exit 1
    }
}

# --- Final Step: Verify ---

Write-Host "Verifying Teams state..." -ForegroundColor Cyan
$teamsUser = Get-CsOnlineUser -Identity $UserPrincipalName `
    | Select-Object DisplayName, LineUri, EnterpriseVoiceEnabled, `
                    OnlineVoiceRoutingPolicy, TenantDialPlan

Write-Host "Teams user state:"
$teamsUser | Format-List