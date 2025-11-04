param (
    [Parameter(Mandatory=$true)]
    [string]$sAMAccountName,

    [Parameter(Mandatory=$true)]
    [string]$NewPassword
)

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    
    # Reset password
    Set-ADAccountPassword -Identity $sAMAccountName -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $NewPassword -Force) -ErrorAction Stop
    
    Write-Output "Password reset successful for $sAMAccountName"
}
catch {
    Write-Error "Failed to reset password: $_"
    throw
}