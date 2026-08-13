#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$RegexSingleline = [System.Text.RegularExpressions.RegexOptions]::Singleline

function Resolve-RepoPath([string]$RelativePath) {
    Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-Text([string]$RelativePath) {
    $path = Resolve-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $RelativePath"
    }
    [IO.File]::ReadAllText($path)
}

function Write-Text([string]$RelativePath, [string]$Content) {
    $path = Resolve-RepoPath $RelativePath
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText($path, $Content, $Utf8NoBom)
}

function Remove-Path([string]$RelativePath) {
    Remove-Item -LiteralPath (Resolve-RepoPath $RelativePath) -Recurse -Force -ErrorAction SilentlyContinue
}

function Replace-RegexOptional([string]$RelativePath, [string]$Pattern, [string]$Replacement) {
    $text = Read-Text $RelativePath
    Write-Text $RelativePath ([regex]::Replace($text, $Pattern, $Replacement, $RegexSingleline))
}

function Assert-Contains([string]$RelativePath, [string]$Needle) {
    if (-not (Read-Text $RelativePath).Contains($Needle)) {
        throw "$RelativePath is missing optimizer invariant: $Needle"
    }
}

function Assert-NotContains([string]$RelativePath, [string]$Needle) {
    if ((Read-Text $RelativePath).Contains($Needle)) {
        throw "$RelativePath still contains optimizer-forbidden content: $Needle"
    }
}

# Stages are intentionally split by concern so an upstream EarTrumpet change fails at
# the narrowest transformation boundary instead of silently producing a partial fork.
. (Resolve-RepoPath 'tools/Optimize-MyMix/01-runtime.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/02-collections.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/03-peak-meter.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/03b-peak-meter-compile-fix.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/03c-visible-peak-scope.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/04-volume-hotpath.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/04b-single-aggregate-peak.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/04c-single-peak-cleanup.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/05-settings-storage.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/06-tray.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/07-output-trim.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/08-viewmodel-lifetime.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/09-icon-cache.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/10-appinfo-cache.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/11-audio-callback-coalescing.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/12-resource-trim.ps1')

Write-Text '.mymix-optimized' "version=4`npeak_meter=30fps-visible-aggregate-smoothed-single-binding`ntrace_release=disabled`naddons=removed`nchannels=removed`nlocales=neutral+ja-JP`nvm_lifetime=explicit-dispose`nicon_cache=bounded-frozen`nappinfo_cache=per-process`naudio_callbacks=coalesced`n"

# Final invariants. These are deliberately behavioral, not just file-existence checks.
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'new Timer(1000.0 / 30.0)'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'DispatcherPriority.Render'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'ShouldSampleAllPeakDevices'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' '_deviceManager.UpdatePeakValues(Default.Id)'
Assert-NotContains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'using System.Threading;'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'AllocHGlobal'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'public virtual void Dispose()'
Assert-NotContains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakValue2'
Assert-NotContains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' 'PeakValue2'
Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'OnPeakValue1Changed'
Assert-NotContains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'PeakValue2'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public override void Dispose()'
Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'ConcurrentDictionary<string, ImageSource>'
Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'image.Freeze()'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ConcurrentDictionary<int, Lazy<IAppInfo>>'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'QueueVolumeUiUpdate();'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'QueueVolumeUiUpdate();'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'Runtime reads are memory-only'
Assert-Contains 'EarTrumpet/MyMix.csproj' '<DefineConstants>X86</DefineConstants>'
Assert-Contains 'EarTrumpet/MyMix.csproj' '<DebugType>none</DebugType>'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Newtonsoft.Json'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'XamlAnimatedGif'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'System.ComponentModel.Composition'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Addons\'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Extensibility\'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Logo-Dark.png'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Logo-Light.png'
Assert-NotContains 'EarTrumpet/App.xaml' 'WelcomeViewModel'
Assert-NotContains 'EarTrumpet/App.xaml.cs' 'RenderMode.SoftwareOnly'
Assert-NotContains 'EarTrumpet/Diagnosis/SnapshotData.cs' 'AddonManager'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'AudioDeviceChannelCollection'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'AudioDeviceSessionChannelCollection'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'UseLogarithmicVolume'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'UseLegacyIcon'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'IsTelemetryEnabled'

Write-Host 'MyMix deep optimization v4 passed.'
