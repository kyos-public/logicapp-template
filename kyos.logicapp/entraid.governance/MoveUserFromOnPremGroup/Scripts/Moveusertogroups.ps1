param (
    [Parameter(Mandatory=$true)]
    [string]$userPrincipalName,

    [Parameter(Mandatory=$false)]
    [string]$department = "",

    [Parameter(Mandatory=$false)]
    [string]$accessPackageJson = "",

    [Parameter(Mandatory=$false)]
    [string]$accessPackageFilePath = ""
)

# Azure Automation runbook error handling
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Import required modules for Azure Automation
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Output "Module ActiveDirectory importé avec succès"
}
catch {
    Write-Error "Impossible d'importer le module ActiveDirectory: $($_.Exception.Message)"
    throw
}

# Initialiser les listes de résultats
$successGroups = @()
$failedGroups = @()
$errors = @()

# Function to get access package data from various sources
function Get-AccessPackageData {
    param(
        [string]$JsonString,
        [string]$FilePath
    )
    
    $accessPackageData = $null
    
    # Priority 1: Use provided JSON string parameter
    if (-not [string]::IsNullOrEmpty($JsonString)) {
        Write-Output "Utilisation du JSON fourni en paramètre"
        try {
            $accessPackageData = $JsonString | ConvertFrom-Json
            Write-Output "JSON paramètre parsé avec succès"
            return $accessPackageData
        }
        catch {
            Write-Warning "Erreur lors du parsing du JSON fourni en paramètre: $($_.Exception.Message)"
        }
    }
    
    # Priority 2: Try to read from file path
    if (-not [string]::IsNullOrEmpty($FilePath) -and (Test-Path $FilePath)) {
        Write-Output "Lecture du fichier JSON depuis: $FilePath"
        try {
            $fileContent = Get-Content -Path $FilePath -Raw
            $accessPackageData = $fileContent | ConvertFrom-Json
            Write-Output "Fichier JSON lu et parsé avec succès"
            return $accessPackageData
        }
        catch {
            Write-Warning "Erreur lors de la lecture du fichier $FilePath : $($_.Exception.Message)"
        }
    }
    
    # Priority 3: Try Azure Automation Asset (for runbook environment)
    try {
        Write-Output "Tentative de récupération depuis Azure Automation Asset"
        $assetContent = Get-AutomationVariable -Name "AccessPackageJson" -ErrorAction Stop
        $accessPackageData = $assetContent | ConvertFrom-Json
        Write-Output "Asset Azure Automation récupéré avec succès"
        return $accessPackageData
    }
    catch {
        Write-Output "Asset Azure Automation non disponible ou inaccessible"
    }
    
    # Priority 4: Try common file paths
    $commonPaths = @(
        "$PSScriptRoot\..\Files\access_package_groupe_ad.json",
        "$PSScriptRoot\..\Files\access_package_default.json", 
        "C:\Scripts\access_package_groupe_ad.json",
        ".\Files\access_package_groupe_ad.json",
        ".\Files\access_package_default.json",
        "$env:TEMP\access_package_groupe_ad.json"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Output "Tentative de lecture depuis: $path"
            try {
                $fileContent = Get-Content -Path $path -Raw
                $accessPackageData = $fileContent | ConvertFrom-Json
                Write-Output "Fichier trouvé et lu avec succès depuis: $path"
                return $accessPackageData
            }
            catch {
                Write-Warning "Erreur lors de la lecture de $path : $($_.Exception.Message)"
            }
        }
    }
    
    # If all fails, throw error
    throw "Impossible de charger les données d'access package depuis toutes les sources disponibles"
}

try {
    # Authenticate to Azure AD (if needed for hybrid scenarios)
    try {
        # For Azure Automation, use Managed Identity or Service Principal
        Write-Output "Initialisation de l'authentification Azure Automation"
        
        # Check if running in Azure Automation context
        if ($env:AUTOMATION_ASSET_ACCOUNTID) {
            Write-Output "Exécution dans Azure Automation détectée"
        }
        
        Write-Output "Authentification configurée avec succès"
    }
    catch {
        Write-Warning "Authentification Azure non disponible, utilisation de l'authentification Windows locale"
    }

    # Parse access package data using the function
    Write-Output "Chargement des données d'access package..."
    try {
        $accessPackageData = Get-AccessPackageData -JsonString $accessPackageJson -FilePath $accessPackageFilePath
        Write-Output "Données d'access package chargées avec succès"
    }
    catch {
        Write-Error "Erreur critique: $($_.Exception.Message)"
        throw
    }

    # Construire la liste des groupes à assigner
    $groupDNs = @()

    # Ajouter les groupes communs (obligatoires pour tous les utilisateurs)
    # NOTE: The 'Commun' access package is an exception and must be ignored completely
    if ($accessPackageData.Commun) {
        Write-Output "Le package 'Commun' est présent dans le fichier mais est ignoré par le runbook"
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

    # Résolution du compte utilisateur avec gestion d'erreur améliorée
    Write-Output "Recherche de l'utilisateur: $userPrincipalName"
    
    try {
        # Try different user identification methods
        $user = $null
        
        # Method 1: By UserPrincipalName
        try {
            $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" -ErrorAction Stop
        }
        catch {
            Write-Output "Recherche par UPN échouée, tentative par SamAccountName"
        }
        
        # Method 2: By SamAccountName if UPN failed
        if (-not $user -and $userPrincipalName -notlike "*@*") {
            try {
                $user = Get-ADUser -Identity $userPrincipalName -ErrorAction Stop
            }
            catch {
                Write-Output "Recherche par SamAccountName échouée"
            }
        }
        
        # Method 3: Extract username from email and search by SamAccountName
        if (-not $user -and $userPrincipalName -like "*@*") {
            $samAccountName = ($userPrincipalName -split "@")[0]
            try {
                $user = Get-ADUser -Identity $samAccountName -ErrorAction Stop
                Write-Output "Utilisateur trouvé par extraction du SamAccountName: $samAccountName"
            }
            catch {
                Write-Output "Recherche par SamAccountName extrait échouée"
            }
        }
        
        if (-not $user) {
            throw "Utilisateur non trouvé avec tous les critères de recherche: $userPrincipalName"
        }
        
        Write-Output "Utilisateur trouvé: $($user.SamAccountName) ($($user.UserPrincipalName))"
    }
    catch {
        throw "Erreur lors de la recherche utilisateur: $($_.Exception.Message)"
    }

    # --- New: Remove user from any full access-packages defined in the generic JSON ---
    $removedPackages = @()
    $removedGroups = @()

    try {
        $genericPath = "$PSScriptRoot\..\Files\access_package_groupe_ad_generic.json"
        if (Test-Path $genericPath) {
            Write-Output "Chargement du fichier generic access package: $genericPath"
            try {
                $genericContent = Get-Content -Path $genericPath -Raw
                $genericPackages = $genericContent | ConvertFrom-Json
                Write-Output "Fichier generic parsé avec succès"

                # Iterate packages (skip Commun)
                foreach ($pkgName in $genericPackages.PSObject.Properties.Name) {
                    if ($pkgName -eq 'Commun') { continue }

                    $pkgGroups = $genericPackages.$pkgName
                    if (-not $pkgGroups) { continue }

                    $isMemberAll = $true

                    foreach ($pkgGroup in $pkgGroups) {
                        try {
                            $member = Get-ADGroupMember -Identity $pkgGroup -Recursive -ErrorAction Stop | Where-Object { $_.SamAccountName -eq $user.SamAccountName }
                            if (-not $member) {
                                $isMemberAll = $false
                                break
                            }
                        }
                        catch {
                            # If group doesn't exist or cannot be queried, treat as not a member for safety
                            Write-Warning "Impossible d'interroger le groupe '$pkgGroup' pour le package '$pkgName': $($_.Exception.Message)"
                            $isMemberAll = $false
                            break
                        }
                    }

                    if ($isMemberAll) {
                        Write-Output "L'utilisateur est membre complet de l'access package '$pkgName' -> suppression de tous les groupes"
                        $removedThisPackage = @()
                        foreach ($pkgGroup in $pkgGroups) {
                            try {
                                Write-Output "Suppression de l'utilisateur du groupe: $pkgGroup"
                                Remove-ADGroupMember -Identity $pkgGroup -Members $user.SamAccountName -Confirm:$false -ErrorAction Stop
                                $removedThisPackage += $pkgGroup
                                $removedGroups += $pkgGroup
                            }
                            catch {
                                Write-Warning "Échec suppression de $pkgGroup : $($_.Exception.Message)"
                                # collect error
                                $errors += "Erreur suppression de $pkgGroup du package $pkgName : $($_.Exception.Message)"
                            }
                        }

                        if ($removedThisPackage.Count -gt 0) { $removedPackages += $pkgName }
                    }
                }
            }
            catch {
                Write-Warning "Erreur lors du parsing du generic access package: $($_.Exception.Message)"
            }
        }
        else {
            Write-Output "Fichier generic access package non trouvé: $genericPath"
        }
    }
    catch {
        Write-Warning "Erreur lors de la vérification/suppression des access packages: $($_.Exception.Message)"
    }


    # Tenter d'ajouter l'utilisateur à chaque groupe avec retry logic
    $maxRetries = 3
    foreach ($groupDN in $groupDNs) {
        $retryCount = 0
        $addedSuccessfully = $false
        
        while ($retryCount -lt $maxRetries -and -not $addedSuccessfully) {
            try {
                Write-Output "Ajout de l'utilisateur au groupe (tentative $($retryCount + 1)/$maxRetries): $groupDN"
                
                # Check if user is already member of the group
                $isMember = Get-ADGroupMember -Identity $groupDN -Recursive | Where-Object {$_.SamAccountName -eq $user.SamAccountName}
                
                if ($isMember) {
                    Write-Output "L'utilisateur est déjà membre du groupe: $groupDN"
                    $successGroups += $groupDN
                    $addedSuccessfully = $true
                }
                else {
                    Add-ADGroupMember -Identity $groupDN -Members $user.SamAccountName -ErrorAction Stop
                    $successGroups += $groupDN
                    $addedSuccessfully = $true
                    Write-Output "Succès pour le groupe: $groupDN"
                }
            }
            catch {
                $retryCount++
                $errorMessage = $_.Exception.Message
                
                if ($retryCount -lt $maxRetries) {
                    Write-Warning "Échec tentative $retryCount pour le groupe '$groupDN': $errorMessage. Nouvelle tentative dans 2 secondes..."
                    Start-Sleep -Seconds 2
                }
                else {
                    $failedGroups += $groupDN
                    $errors += "Échec définitif pour le groupe '$groupDN' après $maxRetries tentatives: $errorMessage"
                    Write-Warning "Échec définitif pour le groupe '$groupDN': $errorMessage"
                }
            }
        }
    }

    # Construire le résultat de succès pour Azure Automation
    $result = @{
        Status = "Success"
        UserPrincipalName = $userPrincipalName
        UserSamAccountName = $user.SamAccountName
        Department = $department
        TotalGroupsProcessed = $groupDNs.Count
        SuccessGroups = $successGroups
        FailedGroups = $failedGroups
        SuccessCount = $successGroups.Count
        FailureCount = $failedGroups.Count
        Errors = $errors
        ExecutionEnvironment = "Azure Automation"
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss UTC")
        RunbookName = $MyInvocation.MyCommand.Name
    }

    Write-Output "Traitement terminé avec succès"
    Write-Output "Groupes ajoutés avec succès: $($successGroups.Count)"
    Write-Output "Groupes en échec: $($failedGroups.Count)"
}
catch {
    # Gestion des erreurs globales pour Azure Automation
    $result = @{
        Status = "Error"
        UserPrincipalName = $userPrincipalName
        Department = $department
        ErrorMessage = $_.Exception.Message
        StackTrace = $_.ScriptStackTrace
        ExecutionEnvironment = "Azure Automation"
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss UTC")
        RunbookName = $MyInvocation.MyCommand.Name
    }
    
    Write-Error "Erreur globale dans le runbook: $($_.Exception.Message)"
    Write-Output "Détails de l'erreur: $($_.ScriptStackTrace)"
}

# Sortie formatée pour Azure Logic Apps
$jsonResult = $result | ConvertTo-Json -Depth 4 -Compress
Write-Output "RUNBOOK_RESULT: $jsonResult"

# Output for Azure Logic Apps consumption
Write-Output "=== RÉSULTAT FINAL ==="
Write-Output "Statut: $($result.Status)"
Write-Output "Utilisateur: $($result.UserPrincipalName)"
Write-Output "Département: $($result.Department)"
Write-Output "Groupes traités: $($result.TotalGroupsProcessed)"
Write-Output "Succès: $($result.SuccessCount)"
Write-Output "Échecs: $($result.FailureCount)"

# Return result for further processing in Logic Apps
return $result
