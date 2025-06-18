# PowerShell script to update Logic App templates for cross-tenant deployment
# This script modifies templates to remove hardcoded values and pre-existing connection dependencies

$templateFolders = @(
    "kyos.logicapp\entraid.governance\AddUserInOnpremGroup",
    "kyos.logicapp\entraid.governance\EntraIDProvisioning", 
    "kyos.logicapp\entraid.governance\FinalTermination",
    "kyos.logicapp\entraid.governance\MoveUserInDisabledOU",
    "kyos.logicapp\entraid.governance\OrderLicenses",
    "kyos.logicapp\entraid.governance\SendPasswordSMS",
    "kyos.logicapp\entraid.governance\SendPasswordToIT"
)

$oldSubscriptionId = "41271998-9818-49dd-8b6a-2ca5ec3a7c50"
$oldResourceGroup = "rg-entra-provisioning-poc_gbo_eu"

Write-Host "Starting Logic App template updates for cross-tenant deployment..." -ForegroundColor Green

foreach ($folder in $templateFolders) {
    Write-Host "Processing folder: $folder" -ForegroundColor Yellow
    
    $jsonFile = Get-ChildItem -Path $folder -Filter "*.json" | Where-Object { $_.Name -notlike "*.parameters.json" }
    
    if ($jsonFile) {
        $templatePath = $jsonFile.FullName
        Write-Host "  Updating template: $($jsonFile.Name)"
        
        # Read the template content
        $content = Get-Content -Path $templatePath -Raw
        
        # Replace hardcoded subscription ID with template function
        $content = $content -replace "41271998-9818-49dd-8b6a-2ca5ec3a7c50", "` + subscription().subscriptionId + `"
        $content = $content -replace "encodeURIComponent\('` + subscription\(\)\.subscriptionId + `'\)", "encodeURIComponent(subscription().subscriptionId)"
        
        # Replace hardcoded resource group with parameter
        $content = $content -replace "rg-entra-provisioning-poc_gbo_eu", "` + parameters('automationResourceGroupName') + `"
        $content = $content -replace "encodeURIComponent\('` + parameters\('automationResourceGroupName'\) + `'\)", "encodeURIComponent(parameters('automationResourceGroupName'))"
        
        # Replace specific automation account names with parameters
        $content = $content -replace "onprem-powershell-execution", "` + parameters('automationAccountName') + `"
        $content = $content -replace "azure-automation-account", "` + parameters('automationAccountName') + `"
        $content = $content -replace "encodeURIComponent\('` + parameters\('automationAccountName'\) + `'\)", "encodeURIComponent(parameters('automationAccountName'))"
        
        # Save the updated content
        Set-Content -Path $templatePath -Value $content -Encoding UTF8
        Write-Host "  Template updated successfully" -ForegroundColor Green
    }
}

Write-Host "All templates have been updated for cross-tenant deployment!" -ForegroundColor Green
Write-Host "Manual steps still required:" -ForegroundColor Yellow
Write-Host "1. Update parameters section in each template" -ForegroundColor White
Write-Host "2. Add connection resources to each template" -ForegroundColor White  
Write-Host "3. Update location references" -ForegroundColor White
Write-Host "4. Update parameter files" -ForegroundColor White
