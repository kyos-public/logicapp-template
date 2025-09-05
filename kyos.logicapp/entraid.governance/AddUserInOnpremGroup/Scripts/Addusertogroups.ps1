param (
    [Parameter(Mandatory=$true)]
    [string]$userPrincipalName,

    [Parameter(Mandatory=$false)]
    [string]$department = "",

    [Parameter(Mandatory=$false)]
    [string]$accessPackageJsonPath = "$PSScriptRoot\..\Files\access_package_groupe_ad.json"
)

# Logic Apps error handling
$ErrorActionPreference = "Stop"

# Initialiser les listes de résultats
$successGroups = @()
$failedGroups = @()
$errors = @()

try {
    # Validate access package JSON path
    if (-not (Test-Path $accessPackageJsonPath)) {
        throw "Fichier access_package_groupe_ad.json non trouvé : $accessPackageJsonPath"
    }

    Write-Output "Lecture du fichier access_package_groupe_ad.json depuis: $accessPackageJsonPath"
    
    # Lire le fichier access package JSON
    $accessPackageData = Get-Content -Path $accessPackageJsonPath -Raw | ConvertFrom-Json
    Write-Output "Fichier access_package_groupe_ad.json lu avec succès"

    # Construire la liste des groupes à assigner
    $groupDNs = @()

    # Ajouter les groupes communs (obligatoires pour tous les utilisateurs)
    if ($accessPackageData.Commun) {
        $groupDNs += $accessPackageData.Commun
        Write-Output "Ajout de $($accessPackageData.Commun.Count) groupes communs"
    }

    # Ajouter les groupes spécifiques au département si fourni
    if (-not [string]::IsNullOrEmpty($department) -and $accessPackageData.PSObject.Properties.Name -contains $department) {
        $departmentGroups = $accessPackageData.$department
        $groupDNs += $departmentGroups
        Write-Output "Ajout de $($departmentGroups.Count) groupes pour le département: $department"
    } elseif (-not [string]::IsNullOrEmpty($department)) {
        Write-Warning "Département '$department' non trouvé dans le fichier access package"
    }

    Write-Output "Total de $($groupDNs.Count) groupes à traiter"

    # Convertir les noms de groupes en DNs complets si nécessaire
    $processedGroups = @()
    foreach ($groupName in $groupDNs) {
        if ($groupName.StartsWith("CN=")) {
            # Déjà un DN complet
            $processedGroups += $groupName
        } elseif ($groupName.Contains("@")) {
            # Adresse email - pas un groupe AD, ignorer
            Write-Warning "Ignorer l'adresse email: $groupName"
            continue
        } else {
            # Nom de groupe simple, essayer de le résoudre
            try {
                $group = Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction Stop
                $processedGroups += $group.DistinguishedName
                Write-Output "Groupe résolu: $groupName -> $($group.DistinguishedName)"
            }
            catch {
                Write-Warning "Impossible de résoudre le groupe: $groupName - $($_.Exception.Message)"
                # Ajouter le nom tel quel pour tenter l'ajout direct
                $processedGroups += $groupName
            }
        }
    }
    
    $groupDNs = $processedGroups
    Write-Output "Total de $($groupDNs.Count) groupes après traitement"

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
