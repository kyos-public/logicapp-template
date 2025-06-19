param (
    [string]$UserPrincipalName
)

try {
    # Import the Active Directory module
    Import-Module ActiveDirectory

    # Retrieve the user from Active Directory
    $user = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'"

    if ($user) {
        # Apply the flag "User must change password at next logon"
        Set-ADUser -Identity $user -ChangePasswordAtLogon $true
        Write-Output "Le flag 'User must change password at next logon' a été appliqué pour l'utilisateur $UserPrincipalName."
    } else {
        Write-Output "Utilisateur $UserPrincipalName non trouvé."
    }
} catch {
    Write-Output "Erreur lors de la mise à jour de l'utilisateur $UserPrincipalName $_"
}