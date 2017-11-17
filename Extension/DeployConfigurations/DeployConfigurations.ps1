[cmdletbinding()]
param (
    $SourcePath,
    $StorageAccountName,
    $AutomationAccountName,
    $ResourceGroupName,
    [Switch]$OverwriteExistingConfigurations
)
Trace-VstsEnteringInvocation $MyInvocation
Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
Initialize-Azure -azurePsVersion $targetAzurePs
Import-Module "$PSScriptRoot\Helper.psm1"

Write-Verbose -Message "Finding all the configurations available under the path: $SourcePath"
$Configs = Get-ChildItem $SourcePath -Recurse -include *.ps1
Write-Verbose -Message "Found $($Configs.Count) configurations"

Write-Verbose -Message "Publishing configurations to specified Azure Automation account"
$PublishedConfigs = Get-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
$Configs | Foreach-Object {
    if ($PublishedConfigs.Name -notcontains $_.BaseName) {
        Write-Verbose -Message "Publishing Configuration file: $($_.Name)"
        $ImportConfigurationParameters = @{
            SourcePath = $_.FullName
            ResourceGroupName = $ResourceGroupName
            Published = $true
            AutomationAccountName = $AutomationAccountName
            Verbose = $True
        }
    }
    elseif ($PublishedConfigs.Name -Contains $_.BaseName -and $OverwriteExistingConfigurations) {
        Write-Verbose -Message "Updating Configuration file: $($_.Name)"
        $ImportConfigurationParameters = @{
            SourcePath = $_.FullName
            ResourceGroupName = $ResourceGroupName
            Published = $true
            AutomationAccountName = $AutomationAccountName
            Verbose = $True
            Force = $True
        }
    }
    else {
        Write-Warning -Message "Configuration already published. To overwrite tick the 'Overwrite Existing Configuration' box on the task."
    }
}

Write-Verbose -Message "Finding all the DSC resources needed by Configurations"
Foreach ($Config in $Configs) {
    Write-Verbose -Message "Checking $($Config.Name) for DSC Resources required"
    $ConfigScript = Get-Ast -Path $Config.FullName
    $AstFilter = {
        param ($ast)
        $ast -is [System.Management.Automation.Language.DynamicKeywordStatementAst]
    }

    $ImportDscResources = $ConfigScript.FindAll($AstFilter,$True) | Where-Object {$_.Extent.Text -like '*Import-DscResource*'}
    Foreach ($Import in $ImportDscResources) {
        $ModuleName = $Import.CommandElements.Where({$_.Value -ne 'Import-DscResource' -and $_.StaticType.Name -eq 'String' -and $_.Value -match '[a-z]+'})
        $ModuleVersion = $Import.CommandElements.Where({$_.Value -ne 'Import-DscResource' -and $_.StaticType.Name -eq 'String' -and $_.Value -notmatch '[a-z]+'})

        Write-Verbose -Message "$($Config.Name) --- Found dependency on $($ModuleName.Value)"
        if (-not (Test-Path -Path "$Env:Temp\$($ModuleName.Value)\$($ModuleVersion.Value)")) {
            $SaveModuleParams = @{
                Name = $ModuleName.Value
                Path = $Env:TEMP
                Repository = (Find-Module -Name $ModuleName.Value)[0].Repository
            }
            if ($ModuleVersion) {
                $SaveModuleParams.Add('RequiredVersion',$ModuleVersion.Value)
                $SaveModuleParams.Repository = (Find-Module -Name $ModuleName.Value -RequiredVersion $ModuleVersion.Value).Repository
            }

            Write-Verbose -Message "$($Config.Name) --- Downloading $($ModuleName.Value) to Temp location"
            Save-Module @SaveModuleParams
        }

        If (-Not (Test-Path -Path "$PSScriptRoot\$($ModuleName.Value).zip")) {
            Write-Verbose -Message "$($Config.Name) --- Compressing $($ModuleName.Value) to upload to Azure Stoarage"
            Compress-Archive -Path "$Env:Temp\$($ModuleName.Value)\$($ModuleVersion.Value)" -DestinationPath "$PSScriptRoot\$($ModuleName.Value).zip"
        }
    }
}

Write-Verbose -Message "Uploading all DSC Resources to Azure Storage"
Write-Verbose -Message "Getting storage account details"
$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName 'testfordeployments' -Name $StorageAccountName

Write-Verbose -Message "Creating a new storage container if one doesn't already exist."
New-AzureStorageContainer -Name 'dscmodules' -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1


$DscResources = Get-ChildItem -Path $PSScriptRoot -Filter *.zip -File
Foreach ($Resource in $DscResources) {


    Write-Verbose -Message "Uploading $($Resource.BaseName) to Azure."
    $DSCLocation = Set-AzureStorageBlobContent -File $Resource.FullName -Blob $Resource.Name -Container 'dscmodules' -Context $StorageAccount.Context -Force

    $DscLocationSasToken = New-AzureStorageBlobSASToken -Blob $DSCLocation.Name -Container 'dscmodules' -StartTime (Get-Date) -ExpiryTime (Get-Date).AddMinutes(5) -Context $StorageAccount.Context -Permission rl -FullUri

    Write-Verbose -Message "$($Resource.BaseName) -- Publishing DSC Resource to Azure Automation."
    $DscUpload = New-AzureRmAutomationModule -Name $Resource.BaseName -ContentLinkUri "$DscLocationSasToken" -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

    While ((Get-AzureRmAutomationModule -Name $Resource.BaseName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue).ProvisioningState -ne 'Succeeded') {
        Write-Verbose -Message "$($Resource.BaseName) -- Waiting for publish to complete"
        Start-Sleep -Seconds 10
    }
}

Write-Verbose -Message "Triggering compilation of each configuration"
$Params = @{
    Credential = $Username
    EnvPrefix = $envPrefix
}
$Configs | foreach-Object {
    Write-Verbose -Message "Compiling $($_.Name) configuration."
    #Start-AzureRmAutomationDscCompilationJob -ConfigurationName $_.BaseName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Parameters $Params -ConfigurationData (iex (Get-Content $PSScriptRoot\..\..\Environments\Generic-WebServer-SQL\Generic-WebServer-SQL.psd1 -raw))
}
