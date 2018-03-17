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

$ConfigurationParametersPath = Get-VstsInput -Name 'ConfigurationParametersPath'
$ResourceGroupName = Get-VstsInput -Name 'ResourceGroupName'
$automationAccountName = Get-VstsInput -Name 'automationAccountName'
$Psd1SourcePath = Get-VstsInput -Name 'Psd1SourcePath'

If (-not (Test-Path -Path $ConfigurationParametersPath)) {
    Write-Error "Invalid path for Configuration parameters path ($ConfigurationParametersPath). Verify the path is correct and the file exists and try again."
    exit -1
}
elseif ($ConfigurationParametersPath.Split('.')[-1] -notIn @('json','psd1')) {
    Write-Error "Invalid file type for Configuration parameters path ($ConfigurationParametersPath). Verify the file is .json or .psd1 and try again."
    exit -1
}
If (-not (Test-Path -Path $Psd1SourcePath)) {
    Write-Error "Invalid path for Configuration Data Source ($Psd1SourcePath). Verify the path is correct and the file exists and try again."
    exit -1
}

If ($ConfigurationParametersPath -match '\.json$') {
    $ConfigurationParameters = Get-Content -Path $ConfigurationParametersPath -Raw | ConvertFrom-Json
}
else {
    $ConfigurationParameters = Import-PowerShellDataFile -Path $ConfigurationParametersPath
}

Write-Verbose -Message "Finding all the configurations available on the automation account"
$AAConfigurations = Get-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $automationAccountName
Write-Verbose -Message "Found $($AAConfigurations.Count) configurations"

Write-Verbose -Message "Triggering compilation of each configuration specified ($($ConfigurationParameters.Configuration.count))"

Foreach ($Configuration in $ConfigurationParameters.Configuration) {

    Write-Verbose -Message "Triggering compilation of $($Configuration.ConfigurationName) configuration"
    $StartCompilationParameters = @{
        ConfigurationName = $Configuration.ConfigurationName
        ResourceGroupName = $ResourceGroupName
        AutomationAccountName = $AutomationAccountName
    }

    If ($ConfigurationParametersPath -match '\.json$') {
        $Configuration = $Configuration.PsObject.Properties | Foreach-Object -Begin { $hash = @{}} -Process {
            $hash[$_.Name] = $_.value
        } -End { $hash }
    }

    $Configuration.Remove('ConfigurationName')

    If ($Configuration.ConfigurationData) {
        Write-Verbose -Message "Finding specified Configuration Data file under path: $Psd1SourcePath"
        $ConfigurationDataPath = Get-ChildItem -Path $Psd1SourcePath -Filter $Configuration.ConfigurationData -Recurse | Select-Object -First 1
        Write-Verbose -Message "Importing Configuration Data file: $($ConfigurationDataPath.FullName)"
        $ConfigurationData = Import-PowerShellDataFile -Path $ConfigurationDataPath.FullName
        $StartCompilationParameters.Add('ConfigurationData',$ConfigurationData)
        $Configuration.Remove('ConfigurationData')
    }

    $StartCompilationParameters.Add('Parameters',$Configuration)

    Start-AzureRmAutomationDscCompilationJob @StartCompilationParameters
}
