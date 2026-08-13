#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function RepoPath([string]$RelativePath) {
    Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function ReadRepo([string]$RelativePath) {
    $path = RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        $Failures.Add("Missing: $RelativePath")
        return ''
    }
    [IO.File]::ReadAllText($path)
}

function Assert-Contains([string]$RelativePath, [string]$Needle) {
    $text = ReadRepo $RelativePath
    if (-not $text.Contains($Needle)) {
        $Failures.Add("$RelativePath does not contain required text: $Needle")
    }
}

function Assert-NotContains([string]$RelativePath, [string]$Needle) {
    $text = ReadRepo $RelativePath
    if ($text.Contains($Needle)) {
        $Failures.Add("$RelativePath still contains forbidden text: $Needle")
    }
}

Assert-Contains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Margin="0,0,16,0"'
Assert-Contains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Margin="0,0,16,0"'
Assert-NotContains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Grid.Column="2" Text="{Binding Volume'
Assert-NotContains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Grid.Column="2"'
Assert-NotContains 'EarTrumpet/UI/Mutable.xaml' 'Mutable_VolumeCellWidth'

foreach ($file in @(
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs',
    'EarTrumpet/DataModel/Audio/Mocks/AudioDevice.cs',
    'EarTrumpet/DataModel/Audio/Mocks/AudioDeviceSession.cs'
)) {
    Assert-NotContains $file 'App.Settings.UseLogarithmicVolume'
    Assert-Contains $file '_volume.ToDisplayVolume()'
    Assert-Contains $file 'value.ToLogVolume()'
}

Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => false;'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => true;'
Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'UseLegacyIcon'
Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'AppSettings _settings'
Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Load'
Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Host'

foreach ($file in @(
    'EarTrumpet/App.config',
    'EarTrumpet/packages.config',
    'EarTrumpet/MyMix.csproj',
    'EarTrumpet/Diagnosis/ErrorReporter.cs'
)) {
    Assert-NotContains $file 'Bugsnag'
}

Assert-Contains 'EarTrumpet/MyMix.csproj' '<AssemblyName>MyMix</AssemblyName>'
Assert-Contains 'MyMix.sln' '= "MyMix", "EarTrumpet\MyMix.csproj"'
Assert-Contains 'EarTrumpet.Package/Package.appxmanifest' '<DisplayName>MyMix</DisplayName>'
Assert-Contains 'EarTrumpet.Package/Package.appxmanifest' 'TaskId="MyMix"'
Assert-Contains 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' '@"Software\MyMix"'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'OpenFeedbackCommand'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'IsTelemetryEnabled'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'File-New-Project/EarTrumpet/issues'

if ($Failures.Count -gt 0) {
    Write-Host 'MyMix refactor validation failed:' -ForegroundColor Red
    foreach ($failure in $Failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'MyMix refactor validation passed.' -ForegroundColor Green
