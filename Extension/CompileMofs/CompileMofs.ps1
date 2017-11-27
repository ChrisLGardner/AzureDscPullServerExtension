[cmdletbinding()]
param (
)

$VerbosePreference = 'Continue'
Trace-VstsEnteringInvocation $MyInvocation
Import-Module $PSScriptRoot\ps_modules\AzureHelpers\AzureHelpers_.psm1
Initialize-Azure
Import-Module "$PSScriptRoot\Helper.psm1"

$Module = Get-Module AzureRM.Automation -ListAvailable

Write-Verbose -Message "AzureRm.Automation version $($Module.Version) found"

$ConfigurationParameters = Get-VstsInput -Name 'ConfigurationParameters'
$ResourceGroupName = Get-VstsInput -Name 'ResourceGroupName'
$automationAccountName = Get-VstsInput -Name 'automationAccountName'
$Psd1SourcePath = Get-VstsInput -Name 'Psd1SourcePath'

Write-Verbose -Message "Finding all the configurations available on the automation account"
$Configs = Get-ChildItem $SourcePath -Recurse -include *.ps1
Write-Verbose -Message "Found $($Configs.Count) configurations"

Write-Verbose -Message "Triggering compilation of each configuration"
$Params = @{
    Credential = 'demoadmin'
    EnvPrefix = 'test123'
}

$ConfigPath = Get-ChildItem -Path $Env:SYSTEM_ARTIFACTSDIRECTORY -Filter *.psd1 -Recurse
$ConfigData = Invoke-Expression (Get-Content -Path $ConfigPath.FullName -raw)

$Configs | foreach-Object {
    Write-Verbose -Message "Compiling $($_.Name) configuration."
    Start-AzureRmAutomationDscCompilationJob -ConfigurationName $_.BaseName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Parameters $Params -ConfigurationData $ConfigData
}
