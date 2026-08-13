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

function Assert-PathMissing([string]$RelativePath) {
    if (Test-Path -LiteralPath (RepoPath $RelativePath)) {
        $Failures.Add("Path should have been removed: $RelativePath")
    }
}

# UI: no dedicated numeric-volume column; slider consumes the returned width.
Assert-Contains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Margin="0,0,16,0"'
Assert-Contains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Margin="0,0,16,0"'
Assert-NotContains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Grid.Column="2" Text="{Binding Volume'
Assert-NotContains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Grid.Column="2"'
Assert-NotContains 'EarTrumpet/UI/Mutable.xaml' 'Mutable_VolumeCellWidth'

# Privacy/branding baseline created by Convert-ToMyMix.
foreach ($file in @('EarTrumpet/App.config', 'EarTrumpet/packages.config', 'EarTrumpet/MyMix.csproj', 'EarTrumpet/Diagnosis/ErrorReporter.cs')) {
    Assert-NotContains $file 'Bugsnag'
}
Assert-Contains 'EarTrumpet/MyMix.csproj' '<AssemblyName>MyMix</AssemblyName>'
Assert-Contains 'MyMix.sln' '= "MyMix", "EarTrumpet\MyMix.csproj"'
Assert-Contains 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' '@"Software\MyMix"'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'OpenFeedbackCommand'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'File-New-Project/EarTrumpet/issues'

$Optimized = Test-Path -LiteralPath (RepoPath '.mymix-optimized')
if ($Optimized) {
    # The optimizer removes obsolete runtime switches entirely.
    foreach ($name in @('UseLegacyIcon', 'IsTelemetryEnabled', 'UseLogarithmicVolume', 'HasShownFirstRun')) {
        Assert-NotContains 'EarTrumpet/AppSettings.cs' $name
    }

    # Peak meter: keep a fixed 30 FPS target, but aggregate one Core Audio meter read per stream,
    # coalesce render work, and smooth release without per-frame unmanaged/managed arrays.
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'new Timer(1000.0 / 30.0)'
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'DispatcherPriority.Render'
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'Interlocked.Exchange(ref _peakUiUpdatePending, 1)'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'AllocHGlobal'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'GetChannelsPeakValues'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 's_peakValue1Changed'
    Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'OnPeakValue1Changed'

    # Runtime/output trimming.
    Assert-Contains '.mymix-optimized' 'version=2'
    Assert-Contains '.mymix-optimized' 'peak_meter=30fps-aggregate-smoothed'
    Assert-Contains 'EarTrumpet/MyMix.csproj' '<DefineConstants>X86</DefineConstants>'
    Assert-Contains 'EarTrumpet/MyMix.csproj' '<DebugType>none</DebugType>'
    foreach ($needle in @('Newtonsoft.Json', 'XamlAnimatedGif', 'System.ComponentModel.Composition', 'Addons\', 'Extensibility\', 'CircularBufferTraceListener.cs', 'FilteredCollectionChain.cs', 'AudioDeviceChannelCollection.cs')) {
        Assert-NotContains 'EarTrumpet/MyMix.csproj' $needle
    }
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'RenderMode.SoftwareOnly'
    Assert-NotContains 'EarTrumpet/App.xaml' 'WelcomeViewModel'
    Assert-NotContains 'EarTrumpet/Diagnosis/SnapshotData.cs' 'AddonManager'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'AudioDeviceChannelCollection'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'AudioDeviceSessionChannelCollection'
    Assert-Contains 'EarTrumpet/DataModel/Storage/Serializer.cs' 'private static class Cache<T>'
    Assert-Contains 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' 'OpenSubKey(s_earTrumpetKey, false)'
    Assert-Contains 'EarTrumpet/AppSettings.cs' 'Runtime reads are memory-only'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'Default.Volume}%'
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'MyMix: '

    foreach ($path in @('EarTrumpet/Addons', 'EarTrumpet/Extensibility', 'EarTrumpet.ColorTool', 'EarTrumpet.Package', '.chocolatey', 'EarTrumpet/Assets/Welcome.gif')) {
        Assert-PathMissing $path
    }

    # Neutral English + Japanese only. Any other satellite resource means updater drifted.
    $localized = @(Get-ChildItem -LiteralPath (RepoPath 'EarTrumpet/Properties') -Filter 'Resources.*.resx' -File | Select-Object -ExpandProperty Name)
    foreach ($name in $localized) {
        if ($name -ne 'Resources.ja-JP.resx') {
            $Failures.Add("Unexpected localized resource remains: $name")
        }
    }
    Assert-Contains 'EarTrumpet/MyMix.csproj' 'Properties\Resources.ja-JP.resx'
    Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Properties\Resources.de-DE.resx'
}
else {
    # Base transform state, before Optimize-MyMix.ps1 runs.
    Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => false;'
    Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => true;'
    Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'UseLegacyIcon'
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Load'
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Host'
}

# GitHub Actions artifact quota: uploads and GitHub-hosted caches are forbidden in either phase.
foreach ($workflow in @('.github/workflows/apply-mymix.yml', '.github/workflows/update-from-eartrumpet.yml')) {
    Assert-NotContains $workflow 'actions/upload-artifact'
    Assert-NotContains $workflow 'actions/cache'
    Assert-Contains $workflow 'deleteArtifact'
}

if ($Failures.Count -gt 0) {
    Write-Host 'MyMix refactor validation failed:' -ForegroundColor Red
    foreach ($failure in $Failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'MyMix refactor validation passed.' -ForegroundColor Green
