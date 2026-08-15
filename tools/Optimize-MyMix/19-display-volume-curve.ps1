# Keep wheel-step semantics in the displayed 0..100 volume domain and soften the
# existing logarithmic mapping without adding a new wheel-time calculation path.
# This stage is ASCII-only for Windows PowerShell 5.1 compatibility.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VolumeCurveRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$VolumeCurveUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-VolumeCurvePath([string]$RelativePath) {
    Join-Path $VolumeCurveRepoRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-VolumeCurveText([string]$RelativePath) {
    $path = Resolve-VolumeCurvePath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $RelativePath" }
    [IO.File]::ReadAllText($path)
}

function Write-VolumeCurveText([string]$RelativePath, [string]$Content) {
    [IO.File]::WriteAllText((Resolve-VolumeCurvePath $RelativePath), $Content, $VolumeCurveUtf8NoBom)
}

function ConvertFrom-VolumeCurveCodePoints([int[]]$CodePoints) {
    -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Set-VolumeCurveResxString([string]$RelativePath, [string]$Name, [string]$Value) {
    $text = Read-VolumeCurveText $RelativePath
    $escaped = [Security.SecurityElement]::Escape($Value)
    $entry = '  <data name="' + $Name + '" xml:space="preserve">' + "`r`n" +
             '    <value>' + $escaped + '</value>' + "`r`n" +
             '  </data>' + "`r`n"
    $pattern = '(?s)  <data\s+name="' + [regex]::Escape($Name) + '"[^>]*>\s*<value>.*?</value>\s*</data>\r?\n?'
    $rx = New-Object Text.RegularExpressions.Regex($pattern)
    $matches = $rx.Matches($text)
    if ($matches.Count -ne 1) { throw "$RelativePath must contain exactly one $Name resource entry." }
    Write-VolumeCurveText $RelativePath ($rx.Replace($text, $entry, 1))
}

# The old factor (5.757) maps a visually half-full slider to only about 5.6% raw
# endpoint amplitude. 3.5 retains the same exponential/logarithmic algorithm while
# mapping display 50% to about 17.4%, making the middle of the gauge substantially
# more usable. This changes one constant only; it adds no operations to the hot path.
$floatPath = 'EarTrumpet/Extensions/FloatExtensions.cs'
$floatText = Read-VolumeCurveText $floatPath
$curvePattern = 'private const double CurveFactor = [0-9]+(?:\.[0-9]+)?;'
$curveMatches = [regex]::Matches($floatText, $curvePattern)
if ($curveMatches.Count -ne 1) { throw "Expected exactly one CurveFactor constant, found $($curveMatches.Count)." }
$floatText = [regex]::Replace($floatText, $curvePattern, 'private const double CurveFactor = 3.5;', 1)
Write-VolumeCurveText $floatPath $floatText

# Make the setting describe what it already controls: percentage points of the visible
# 0..100 gauge per wheel event. The wheel path continues to add the cached integer to
# the display-domain Volume property, which then passes through ToLogVolume().
Set-VolumeCurveResxString 'EarTrumpet/Properties/Resources.resx' 'SettingsVolumeStepText' 'Wheel step (% of displayed range)'
Set-VolumeCurveResxString 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsVolumeStepText' (ConvertFrom-VolumeCurveCodePoints @(0x30DB,0x30A4,0x30FC,0x30EB,0x0031,0x6BB5,0x306E,0x97F3,0x91CF,0x5909,0x66F4,0x5E45,0xFF08,0x8868,0x793A,0x7BC4,0x56F2,0x0020,0x0025,0xFF09))

$mouseVmPath = 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs'
$mouseVm = Read-VolumeCurveText $mouseVmPath
$mouseVm = $mouseVm.Replace('?? "Volume step (%)";', '?? "Wheel step (% of displayed range)";')
Write-VolumeCurveText $mouseVmPath $mouseVm

# Semantic/performance invariants: do not introduce a raw-volume wheel calculation.
$app = Read-VolumeCurveText 'EarTrumpet/App.xaml.cs'
if (-not $app.Contains('CollectionViewModel.Default?.IncrementVolume(Math.Sign(wheelDelta) * Settings.VolumeStep);')) {
    throw 'Tray wheel no longer applies the cached VolumeStep directly to displayed volume.'
}
$deviceVm = Read-VolumeCurveText 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs'
if (-not $deviceVm.Contains('public void IncrementVolume(int delta) => Volume += delta;')) {
    throw 'DeviceViewModel no longer applies wheel delta in the displayed 0..100 volume domain.'
}
$sessionVm = Read-VolumeCurveText 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs'
if (-not $sessionVm.Contains('get => _stream.Volume.ToVolumeInt();') -or -not $sessionVm.Contains('set => _stream.Volume = value / 100f;')) {
    throw 'AudioSessionViewModel Volume is no longer the displayed 0..100 volume domain.'
}
foreach ($audioPath in @('EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs','EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs')) {
    $audio = Read-VolumeCurveText $audioPath
    if (-not $audio.Contains('var rawVolume = displayVolume.ToLogVolume();')) {
        throw "$audioPath no longer maps displayed volume through ToLogVolume()."
    }
}

$floatFinal = Read-VolumeCurveText $floatPath
if (-not $floatFinal.Contains('private const double CurveFactor = 3.5;')) { throw 'Gentler logarithmic curve factor is missing.' }
if (-not $floatFinal.Contains('Math.Exp(CurveFactor * val) * InverseCurveScale')) { throw 'Logarithmic volume algorithm changed unexpectedly.' }
if (-not $floatFinal.Contains('(Math.Log(val) + CurveFactor) / CurveFactor')) { throw 'Inverse logarithmic display mapping changed unexpectedly.' }
if (-not (Read-VolumeCurveText 'EarTrumpet/Properties/Resources.resx').Contains('<value>Wheel step (% of displayed range)</value>')) { throw 'Neutral wheel-step label is incorrect.' }

Write-Host 'Displayed-range wheel step and gentler logarithmic volume curve repair passed.'
