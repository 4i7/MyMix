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

function Assert-Matches([string]$RelativePath, [string]$Pattern) {
    $text = ReadRepo $RelativePath
    if ($text -notmatch $Pattern) {
        $Failures.Add("$RelativePath does not match required pattern: $Pattern")
    }
}

function Assert-NotMatches([string]$RelativePath, [string]$Pattern) {
    $text = ReadRepo $RelativePath
    if ($text -match $Pattern) {
        $Failures.Add("$RelativePath matches forbidden pattern: $Pattern")
    }
}

function Assert-PathMissing([string]$RelativePath) {
    if (Test-Path -LiteralPath (RepoPath $RelativePath)) {
        $Failures.Add("Path should have been removed: $RelativePath")
    }
}

function Assert-PathExists([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (RepoPath $RelativePath))) {
        $Failures.Add("Required path is missing: $RelativePath")
    }
}

# Public repository documentation/provenance must survive every clean upstream regeneration.
foreach ($doc in @('README.md', 'PRIVACY.md', 'COMPILING.md', 'CONTRIBUTING.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE', 'UPSTREAM_README.md')) {
    Assert-PathExists $doc
}
Assert-Contains 'README.md' 'not an official EarTrumpet release'
Assert-Contains 'README.md' 'retains the upstream [LICENSE](LICENSE) verbatim'
Assert-Contains 'PRIVACY.md' 'does not automatically submit telemetry'
Assert-Contains 'THIRD_PARTY_NOTICES.md' 'explicit excluded entities'
Assert-Contains 'tools/Update-FromEarTrumpet.ps1' '$MyMixDocs'
Assert-Contains 'tools/Update-FromEarTrumpet.ps1' 'local LICENSE does not exactly match the imported EarTrumpet LICENSE'

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
    foreach ($name in @('UseLegacyIcon', 'IsTelemetryEnabled', 'UseLogarithmicVolume', 'HasShownFirstRun')) {
        Assert-NotContains 'EarTrumpet/AppSettings.cs' $name
    }

    # Peak meter remains a fixed 30 FPS experience. Work is reduced by aggregate Core Audio reads,
    # visible-device scoping, one peak binding per stream, cached topology snapshots, stale-frame
    # dropping, and cheap release smoothing rather than by lowering the requested frame rate.
    $peakCollection = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
    Assert-Contains $peakCollection 'new Timer(1000.0 / 30.0)'
    Assert-Contains $peakCollection 'DispatcherPriority.Render'
    Assert-Contains $peakCollection 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
    Assert-Contains $peakCollection 'ShouldSampleAllPeakDevices'
    Assert-Contains $peakCollection '_deviceManager.UpdatePeakValues();'
    Assert-Contains $peakCollection '_deviceManager.UpdatePeakValues(Default.Id)'
    Assert-Contains $peakCollection 'foreach (var device in AllDevices)'
    # Regression guard for a previously discovered compile-clean but runtime-fatal recursion bug.
    Assert-NotMatches $peakCollection '(?ms)private void UpdatePeakValuesForVisibleSurfaces\(\).*?if \(ShouldSampleAllPeakDevices\).*?\{\s*UpdatePeakValuesForVisibleSurfaces\(\);'
    Assert-NotMatches $peakCollection '(?ms)private void UpdatePeakForegroundForVisibleSurfaces\(\).*?if \(ShouldSampleAllPeakDevices\).*?\{\s*UpdatePeakForegroundForVisibleSurfaces\(\);'
    Assert-NotContains $peakCollection 'using System.Threading;'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'AllocHGlobal'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'GetChannelsPeakValues'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 's_peakValue1Changed'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakValue2'
    Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'OnPeakValue1Changed'
    Assert-NotContains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'PeakValue2'
    Assert-NotContains 'EarTrumpet/UI/Views/AppItemView.xaml' 'PeakValue2'
    Assert-NotContains 'EarTrumpet/UI/Views/DeviceView.xaml' 'PeakValue2'

    # Runtime/output trimming and hot paths.
    Assert-Contains '.mymix-optimized' 'version=3'
    Assert-Contains '.mymix-optimized' 'peak_meter=30fps-visible-aggregate-smoothed-single-binding'
    Assert-Contains '.mymix-optimized' 'vm_lifetime=explicit-dispose'
    Assert-Contains '.mymix-optimized' 'icon_cache=bounded-frozen'
    Assert-Contains '.mymix-optimized' 'appinfo_cache=per-process'
    Assert-Contains '.mymix-optimized' 'audio_callbacks=coalesced'
    Assert-Contains '.mymix-optimized' 'public_hardening=unbranded-icons-safe-finalizer-smoke-test'
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
    Assert-NotContains $peakCollection 'Default.Volume}%'
    Assert-Contains $peakCollection 'MyMix: '
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'public virtual void Dispose()'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs' 'public override void Dispose()'
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public override void Dispose()'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs' '~AppItemViewModel'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' '~DeviceViewModel'
    Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'ConcurrentDictionary<string, ImageSource>'
    Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'image.Freeze()'
    Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ConcurrentDictionary<int, Lazy<IAppInfo>>'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'QueueVolumeUiUpdate();'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'QueueVolumeUiUpdate();'

    # Public-release hardening: no upstream application artwork bundled as MyMix branding,
    # no user-triggerable deliberate crash, safe finalizer cleanup, and a deterministic CI startup mode.
    foreach ($needle in @('Logo-Dark.png', 'Logo-Light.png', 'Icon-Dark.ico', 'Icon-Light.ico')) {
        Assert-NotContains 'EarTrumpet/MyMix.csproj' $needle
    }
    foreach ($path in @('EarTrumpet/Assets/Icon-Light.ico', 'EarTrumpet/Assets/Icon-Dark.ico')) { Assert-PathMissing $path }
    Assert-NotContains 'EarTrumpet/App.xaml' 'EarTrumpetIconLight'
    Assert-NotContains 'EarTrumpet/App.xaml' 'EarTrumpetIconDark'
    Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'IconKind.EarTrumpet'
    Assert-Contains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'SystemIcons.Application.Clone()'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'intentional local diagnostic crash'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionCollection.cs' '_sessionManager?.UnregisterSessionNotification(this);'
    Assert-Contains $peakCollection 'allExisting.Dispose();'
    Assert-Contains $peakCollection 'AllDevices[i].Dispose();'
    Assert-Contains 'EarTrumpet/Interop/Helpers/SingleInstanceAppMutex.cs' 'MYMIX_MUTEX_SUFFIX'
    Assert-Contains 'EarTrumpet/App.xaml.cs' '--smoke-test'
    Assert-Contains 'EarTrumpet/App.xaml.cs' 'DispatcherPriority.ApplicationIdle'
    Assert-Contains 'EarTrumpet/Diagnosis/LocalDataExporter.cs' 'MyMix-diagnostics-'
    Assert-NotContains 'EarTrumpet/Properties/Resources.resx' 'eartrumpet.app/jmp/fixfonts'

    foreach ($path in @(
        'EarTrumpet/Addons', 'EarTrumpet/Extensibility', 'EarTrumpet.ColorTool', 'EarTrumpet.Package', '.chocolatey',
        'EarTrumpet/Assets/Welcome.gif', 'EarTrumpet/Assets/Logo-Dark.png', 'EarTrumpet/Assets/Logo-Light.png'
    )) {
        Assert-PathMissing $path
    }

    # Neutral English + Japanese only.
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

# Artifact/caching invariant: GitHub-hosted artifact storage is never used by MyMix workflows.
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

Write-Host 'MyMix refactor/public-release validation passed.' -ForegroundColor Green
