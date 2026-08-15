#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-RepoText([string]$relativePath) {
    [IO.File]::ReadAllText((Join-Path $repoRoot $relativePath))
}

function Write-RepoText([string]$relativePath, [string]$content) {
    [IO.File]::WriteAllText((Join-Path $repoRoot $relativePath), $content, $utf8)
}

function Insert-AfterOnce([string]$text, [string]$needle, [string]$addition, [string]$label) {
    if ($text.Contains($addition.Trim())) { return $text }
    $index = $text.IndexOf($needle, [StringComparison]::Ordinal)
    if ($index -lt 0) { throw "Anchor not found for $label" }
    $insertAt = $index + $needle.Length
    return $text.Substring(0, $insertAt) + "`r`n" + $addition.TrimEnd() + $text.Substring($insertAt)
}

Push-Location $repoRoot
try {
    .\tools\Optimize-MyMix\19-display-volume-curve.ps1

    $optimizerPath = 'tools/Optimize-MyMix.ps1'
    $optimizer = Read-RepoText $optimizerPath
    $stage18 = ". (Resolve-RepoPath 'tools/Optimize-MyMix/18-settings-ui-fix.ps1')"
    $stage19 = ". (Resolve-RepoPath 'tools/Optimize-MyMix/19-display-volume-curve.ps1')"
    if (-not $optimizer.Contains($stage19)) {
        if (-not $optimizer.Contains($stage18)) { throw 'Stage 18 anchor missing from optimizer.' }
        $optimizer = $optimizer.Replace($stage18, $stage18 + "`r`n" + $stage19)
    }
    $markerOld = 'control_shortcuts=mute-cycle-output-configurable-step`nstartup=opt-in-hkcu-run`n'
    $markerNew = 'control_shortcuts=mute-cycle-output-configurable-step`nvolume_control=logarithmic-3.5-display-step`nstartup=opt-in-hkcu-run`n'
    if (-not $optimizer.Contains('volume_control=logarithmic-3.5-display-step')) {
        if (-not $optimizer.Contains($markerOld)) { throw 'Optimizer metadata anchor missing.' }
        $optimizer = $optimizer.Replace($markerOld, $markerNew)
    }
    $wheelInvariant = "Assert-Contains 'EarTrumpet/App.xaml.cs' 'Math.Sign(wheelDelta) * Settings.VolumeStep'"
    $volumeInvariants = @'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public void IncrementVolume(int delta) => Volume += delta;'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'get => _stream.Volume.ToVolumeInt();'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'set => _stream.Volume = value / 100f;'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'var rawVolume = displayVolume.ToLogVolume();'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'var rawVolume = displayVolume.ToLogVolume();'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' 'private const double CurveFactor = 3.5;'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' 'Math.Exp(CurveFactor * val) * InverseCurveScale'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' '(Math.Log(val) + CurveFactor) / CurveFactor'
Assert-Contains 'EarTrumpet/Properties/Resources.resx' '<value>Wheel step (% of displayed range)</value>'
'@
    $optimizer = Insert-AfterOnce $optimizer $wheelInvariant $volumeInvariants 'optimizer display-volume invariants'
    $optimizerMarker = "Assert-Contains '.mymix-optimized' 'startup=opt-in-hkcu-run'"
    $optimizerMarkerAdd = "Assert-Contains '.mymix-optimized' 'volume_control=logarithmic-3.5-display-step'"
    $optimizer = Insert-AfterOnce $optimizer $optimizerMarker $optimizerMarkerAdd 'optimizer metadata invariant'
    Write-RepoText $optimizerPath $optimizer

    $metadataPath = '.mymix-optimized'
    $metadata = Read-RepoText $metadataPath
    if (-not $metadata.Contains('volume_control=logarithmic-3.5-display-step')) {
        $metadataAnchor = "control_shortcuts=mute-cycle-output-configurable-step`nstartup=opt-in-hkcu-run"
        $metadataReplacement = "control_shortcuts=mute-cycle-output-configurable-step`nvolume_control=logarithmic-3.5-display-step`nstartup=opt-in-hkcu-run"
        if (-not $metadata.Contains($metadataAnchor)) { throw 'Materialized optimizer metadata anchor missing.' }
        $metadata = $metadata.Replace($metadataAnchor, $metadataReplacement)
        Write-RepoText $metadataPath $metadata
    }

    $testPath = 'tools/Test-MyMixRefactor.ps1'
    $test = Read-RepoText $testPath
    $test = Insert-AfterOnce $test $wheelInvariant $volumeInvariants 'test display-volume invariants'
    $markerListOld = "'control_shortcuts=mute-cycle-output-configurable-step','startup=opt-in-hkcu-run'"
    $markerListNew = "'control_shortcuts=mute-cycle-output-configurable-step','volume_control=logarithmic-3.5-display-step','startup=opt-in-hkcu-run'"
    if (-not $test.Contains("'volume_control=logarithmic-3.5-display-step'")) {
        if (-not $test.Contains($markerListOld)) { throw 'Test metadata list anchor missing.' }
        $test = $test.Replace($markerListOld, $markerListNew)
    }
    $stage17Invariant = @'
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/17-startup-option.ps1'"
'@.Trim()
    $stage19Invariant = @'
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/19-display-volume-curve.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/19-display-volume-curve.ps1'
'@
    $test = Insert-AfterOnce $test $stage17Invariant $stage19Invariant 'stage 19 preservation invariant'
    Write-RepoText $testPath $test

    .\tools\Test-MyMixRefactor.ps1
}
finally {
    Pop-Location
}
