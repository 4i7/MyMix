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

# Optimization stages are dot-sourced so future upstream drift remains reviewable by area.
. (Resolve-RepoPath 'tools/Optimize-MyMix/01-runtime.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/02-collections.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/03-peak-meter.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/03b-peak-meter-compile-fix.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/04-volume-hotpath.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/05-settings-storage.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/06-tray.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/07-output-trim.ps1')

Write-Text '.mymix-optimized' "version=2`npeak_meter=30fps-aggregate-smoothed`ntrace_release=disabled`naddons=removed`nchannels=removed`nlocales=neutral+ja-JP`n"

# Final drift/invariant checks. Future upstream changes must fail instead of silently
# producing a partially optimized MyMix.
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'new Timer(1000.0 / 30.0)'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'DispatcherPriority.Render'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
Assert-NotContains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'using System.Threading;'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'OnPeakValue1Changed'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'Runtime reads are memory-only'
Assert-Contains 'EarTrumpet/MyMix.csproj' '<DefineConstants>X86</DefineConstants>'
Assert-Contains 'EarTrumpet/MyMix.csproj' '<DebugType>none</DebugType>'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Newtonsoft.Json'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'XamlAnimatedGif'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'System.ComponentModel.Composition'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Addons\'
Assert-NotContains 'EarTrumpet/MyMix.csproj' 'Extensibility\'
Assert-NotContains 'EarTrumpet/App.xaml' 'WelcomeViewModel'
Assert-NotContains 'EarTrumpet/App.xaml.cs' 'RenderMode.SoftwareOnly'
Assert-NotContains 'EarTrumpet/Diagnosis/SnapshotData.cs' 'AddonManager'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'AudioDeviceChannelCollection'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'AudioDeviceSessionChannelCollection'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'UseLogarithmicVolume'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'UseLegacyIcon'
Assert-NotContains 'EarTrumpet/AppSettings.cs' 'IsTelemetryEnabled'

Write-Host 'MyMix deep optimization v2 passed.'
