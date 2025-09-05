param (
    [Parameter(Mandatory=$true)]
    [string]$userPrincipalName,

    [Parameter(Mandatory=$false)]
    [string]$department = "",

    [Parameter(Mandatory=$false)]
    [string]$groupsJsonPath = "$PSScriptRoot\..\Files\Groups.json"
)

# Logic Apps error handling
$ErrorActionPreference = "Stop"

# Initialiser les listes de résultats
$successGroups = @()
$failedGroups = @()
$errors = @()

try {
    # Validate Groups.json path
    if (-not (Test-Path $groupsJsonPath)) {
        throw "Fichier Groups.json non trouvé : $groupsJsonPath"
    }

    Write-Output "Lecture du fichier Groups.json depuis: $groupsJsonPath"
    
    # Lire le fichier Groups.json
    $groupsData = Get-Content -Path $groupsJsonPath -Raw | ConvertFrom-Json
    Write-Output "Fichier Groups.json lu avec succès"

    # Construire la liste des groupes à assigner
    $groupDNs = @()

    # Ajouter les groupes de base (obligatoires pour tous les utilisateurs)
    if ($groupsData.baseGroups) {
        $groupDNs += $groupsData.baseGroups
        Write-Output "Ajout de $($groupsData.baseGroups.Count) groupes de base"
    }

    # Ajouter les groupes spécifiques au département si fourni
    if (-not [string]::IsNullOrEmpty($department) -and $groupsData.departmentGroups.PSObject.Properties.Name -contains $department) {
        $departmentGroups = $groupsData.departmentGroups.$department
        $groupDNs += $departmentGroups
        Write-Output "Ajout de $($departmentGroups.Count) groupes pour le département: $department"
    }

    Write-Output "Total de $($groupDNs.Count) groupes à traiter"

    # Résolution du compte utilisateur
    Write-Output "Recherche de l'utilisateur: $userPrincipalName"
    $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" -ErrorAction Stop
    
    if ($null -eq $user) {
        throw "Utilisateur non trouvé : $userPrincipalName"
    }
    
    Write-Output "Utilisateur trouvé: $($user.SamAccountName)"

    # Tenter d'ajouter l'utilisateur à chaque groupe
    foreach ($groupDN in $groupDNs) {
        try {
            Write-Output "Ajout de l'utilisateur au groupe: $groupDN"
            Add-ADGroupMember -Identity $groupDN -Members $user.SamAccountName -ErrorAction Stop
            $successGroups += $groupDN
            Write-Output "Succès pour le groupe: $groupDN"
        }
        catch {
            $errorMessage = $_.Exception.Message
            $failedGroups += $groupDN
            $errors += "Échec pour le groupe '$groupDN': $errorMessage"
            Write-Warning "Échec pour le groupe '$groupDN': $errorMessage"
        }
    }

    # Construire le résultat de succès
    $result = @{
        Status = "Success"
        UserPrincipalName = $userPrincipalName
        Department = $department
        TotalGroupsProcessed = $groupDNs.Count
        SuccessGroups = $successGroups
        FailedGroups = $failedGroups
        SuccessCount = $successGroups.Count
        FailureCount = $failedGroups.Count
        Errors = $errors
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    Write-Output "Traitement terminé avec succès"
}
catch {
    # Gestion des erreurs globales pour Logic Apps
    $result = @{
        Status = "Error"
        UserPrincipalName = $userPrincipalName
        Department = $department
        ErrorMessage = $_.Exception.Message
        StackTrace = $_.ScriptStackTrace
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    Write-Error "Erreur globale: $($_.Exception.Message)"
}

# Sortie formatée pour Logic Apps
$jsonResult = $result | ConvertTo-Json -Depth 3 -Compress
Write-Output "RESULT_JSON: $jsonResult"

# Retourner le résultat pour Logic Apps
return $result
