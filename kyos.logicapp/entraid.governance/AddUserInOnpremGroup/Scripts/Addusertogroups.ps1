param (
    [Parameter(Mandatory=$true)]
    [string]$userPrincipalName,

    [Parameter(Mandatory=$true)]
    [string[]]$groupDNs
)

# Initialiser les listes de résultats
$successGroups = @()
$failedGroups = @()

# Résolution du compte utilisateur
$user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'"
if ($null -eq $user) {
    throw "Utilisateur non trouvé : $userPrincipalName"
}

# Tenter d'ajouter l'utilisateur à chaque groupe
foreach ($groupDN in $groupDNs) {
    try {
        Add-ADGroupMember -Identity $groupDN -Members $user.SamAccountName -ErrorAction Stop
        $successGroups += $groupDN
    }
    catch {
        $failedGroups += $groupDN
    }
}

# Retourner les résultats
$result = @{
    SuccessGroups = $successGroups
    FailedGroups = $failedGroups
}
$result | ConvertTo-Json
