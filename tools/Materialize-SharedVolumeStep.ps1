#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Repo-Path([string]$relativePath) {
    Join-Path $repoRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-RepoText([string]$relativePath) {
    $path = Repo-Path $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $relativePath" }
    [IO.File]::ReadAllText($path)
}

function Write-RepoText([string]$relativePath, [string]$content) {
    [IO.File]::WriteAllText((Repo-Path $relativePath), $content, $utf8)
}

function Replace-LiteralOnce([string]$text, [string]$oldValue, [string]$newValue, [string]$label) {
    $first = $text.IndexOf($oldValue, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Anchor missing for $label" }
    $second = $text.IndexOf($oldValue, $first + $oldValue.Length, [StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Anchor is not unique for $label" }
    return $text.Substring(0, $first) + $newValue + $text.Substring($first + $oldValue.Length)
}

function Insert-AfterOnce([string]$text, [string]$needle, [string]$addition, [string]$label) {
    if ($text.Contains($addition.Trim())) { return $text }
    $index = $text.IndexOf($needle, [StringComparison]::Ordinal)
    if ($index -lt 0) { throw "Anchor missing for $label" }
    $second = $text.IndexOf($needle, $index + $needle.Length, [StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Anchor is not unique for $label" }
    $insertAt = $index + $needle.Length
    return $text.Substring(0, $insertAt) + "`r`n" + $addition.TrimEnd() + $text.Substring($insertAt)
}

Push-Location $repoRoot
try {
    .\tools\Optimize-MyMix\20-shared-volume-step.ps1

    $optimizerPath = 'tools/Optimize-MyMix.ps1'
    $optimizer = Read-RepoText $optimizerPath
    $stage19 = ". (Resolve-RepoPath 'tools/Optimize-MyMix/19-display-volume-curve.ps1')"
    $stage20 = ". (Resolve-RepoPath 'tools/Optimize-MyMix/20-shared-volume-step.ps1')"
    if (-not $optimizer.Contains($stage20)) {
        $optimizer = Insert-AfterOnce $optimizer $stage19 $stage20 'optimizer stage 20'
    }

    $optimizerMarkerOld = 'volume_control=logarithmic-3.5-display-step`nstartup=opt-in-hkcu-run`n'
    $optimizerMarkerNew = 'volume_control=logarithmic-3.5-display-step`nvolume_step=shared-tray-and-slider`nstartup=opt-in-hkcu-run`n'
    if (-not $optimizer.Contains('volume_step=shared-tray-and-slider')) {
        $optimizer = Replace-LiteralOnce $optimizer $optimizerMarkerOld $optimizerMarkerNew 'optimizer metadata writer'
    }

    $oldLabelInvariant = "Assert-Contains 'EarTrumpet/Properties/Resources.resx' '<value>Wheel step (% of displayed range)</value>'"
    $newLabelInvariant = "Assert-Contains 'EarTrumpet/Properties/Resources.resx' '<value>Volume step</value>'"
    if ($optimizer.Contains($oldLabelInvariant)) {
        $optimizer = Replace-LiteralOnce $optimizer $oldLabelInvariant $newLabelInvariant 'optimizer concise label invariant'
    } elseif (-not $optimizer.Contains($newLabelInvariant)) {
        throw 'Optimizer volume-step resource invariant is missing.'
    }

    $optimizerSharedInvariants = @'
Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'ChangePositionByAmount(Math.Sign(e.Delta) * (EarTrumpet.App.Settings?.VolumeStep ?? 2));'
Assert-NotContains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'ChangePositionByAmount(Math.Sign(e.Delta) * 2.0);'
Assert-Contains 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' '?? "Volume step";'
Assert-NotContains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Text="1%"'
Assert-NotContains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Text="10%"'
'@
    $optimizer = Insert-AfterOnce $optimizer $newLabelInvariant $optimizerSharedInvariants 'optimizer shared volume-step invariants'

    $optimizerMarkerAnchor = "Assert-Contains '.mymix-optimized' 'volume_control=logarithmic-3.5-display-step'"
    $optimizerMarkerAdd = "Assert-Contains '.mymix-optimized' 'volume_step=shared-tray-and-slider'"
    $optimizer = Insert-AfterOnce $optimizer $optimizerMarkerAnchor $optimizerMarkerAdd 'optimizer shared volume-step marker invariant'
    Write-RepoText $optimizerPath $optimizer

    $metadataPath = '.mymix-optimized'
    $metadata = Read-RepoText $metadataPath
    if (-not $metadata.Contains('volume_step=shared-tray-and-slider')) {
        $metadataOld = "volume_control=logarithmic-3.5-display-step`nstartup=opt-in-hkcu-run"
        $metadataNew = "volume_control=logarithmic-3.5-display-step`nvolume_step=shared-tray-and-slider`nstartup=opt-in-hkcu-run"
        $metadata = Replace-LiteralOnce $metadata $metadataOld $metadataNew 'materialized optimizer metadata'
        Write-RepoText $metadataPath $metadata
    }

    $testPath = 'tools/Test-MyMixRefactor.ps1'
    $test = Read-RepoText $testPath
    if ($test.Contains($oldLabelInvariant)) {
        $test = Replace-LiteralOnce $test $oldLabelInvariant $newLabelInvariant 'test concise label invariant'
    } elseif (-not $test.Contains($newLabelInvariant)) {
        throw 'Test volume-step resource invariant is missing.'
    }
    $test = Insert-AfterOnce $test $newLabelInvariant $optimizerSharedInvariants 'test shared volume-step invariants'

    $testMarkerOld = "'volume_control=logarithmic-3.5-display-step','startup=opt-in-hkcu-run'"
    $testMarkerNew = "'volume_control=logarithmic-3.5-display-step','volume_step=shared-tray-and-slider','startup=opt-in-hkcu-run'"
    if (-not $test.Contains("'volume_step=shared-tray-and-slider'")) {
        $test = Replace-LiteralOnce $test $testMarkerOld $testMarkerNew 'test metadata list'
    }

    $testStage19 = @'
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/19-display-volume-curve.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/19-display-volume-curve.ps1'
'@.Trim()
    $testStage20 = @'
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/20-shared-volume-step.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/20-shared-volume-step.ps1'
'@
    $test = Insert-AfterOnce $test $testStage19 $testStage20 'test stage 20 preservation'
    Write-RepoText $testPath $test

    $releasePath = '.github/workflows/release.yml'
    $release = Read-RepoText $releasePath
    $oldReleaseBullet1 = "              '- Fix Japanese settings labels on the mouse settings page.',"
    $newReleaseBullet1 = "              '- Apply the configured 1-10% volume step to mouse-wheel changes on in-window device/app sliders as well as the taskbar icon.',"
    if ($release.Contains($oldReleaseBullet1)) {
        $release = Replace-LiteralOnce $release $oldReleaseBullet1 $newReleaseBullet1 'release shared volume-step bullet'
    }
    $oldReleaseBullet2 = "              '- Replace the volume-step selector with a non-editable 1-10% slider that snaps to whole percentages.',"
    $newReleaseBullet2 = "              '- Keep the non-editable 1-10% slider, simplify its label, and remove redundant 1%/10% endpoint captions.',"
    if ($release.Contains($oldReleaseBullet2)) {
        $release = Replace-LiteralOnce $release $oldReleaseBullet2 $newReleaseBullet2 'release concise settings bullet'
    }
    $releaseAnchor = "              '- Remove the volume-step ComboBox path that could leak the settings-search placeholder into the control.',"
    $releaseCurveBullet = "              '- Keep the gentler logarithmic volume curve while preserving the existing display-domain volume path.',"
    if (-not $release.Contains($releaseCurveBullet)) {
        $release = Insert-AfterOnce $release $releaseAnchor $releaseCurveBullet 'release logarithmic curve bullet'
    }
    Write-RepoText $releasePath $release

    .\tools\Test-MyMixRefactor.ps1
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
