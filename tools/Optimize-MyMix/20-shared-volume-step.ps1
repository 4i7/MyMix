# Apply the configured VolumeStep to in-window volume sliders as well as tray-wheel
# handling, and keep the settings UI concise. This stage is ASCII-only for Windows
# PowerShell 5.1 compatibility; Japanese text is emitted from code points.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SharedStepRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SharedStepUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-SharedStepPath([string]$RelativePath) {
    Join-Path $SharedStepRepoRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-SharedStepText([string]$RelativePath) {
    $path = Resolve-SharedStepPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $RelativePath" }
    [IO.File]::ReadAllText($path)
}

function Write-SharedStepText([string]$RelativePath, [string]$Content) {
    [IO.File]::WriteAllText((Resolve-SharedStepPath $RelativePath), $Content, $SharedStepUtf8NoBom)
}

function ConvertFrom-SharedStepCodePoints([int[]]$CodePoints) {
    -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Set-SharedStepResxString([string]$RelativePath, [string]$Name, [string]$Value) {
    $text = Read-SharedStepText $RelativePath
    $escaped = [Security.SecurityElement]::Escape($Value)
    $entry = '  <data name="' + $Name + '" xml:space="preserve">' + "`r`n" +
             '    <value>' + $escaped + '</value>' + "`r`n" +
             '  </data>' + "`r`n"
    $pattern = '(?s)  <data\s+name="' + [regex]::Escape($Name) + '"[^>]*>\s*<value>.*?</value>\s*</data>\r?\n?'
    $rx = New-Object Text.RegularExpressions.Regex($pattern)
    $matches = $rx.Matches($text)
    if ($matches.Count -ne 1) { throw "$RelativePath must contain exactly one $Name resource entry." }
    Write-SharedStepText $RelativePath ($rx.Replace($text, $entry, 1))
}

# VolumeSlider handles wheel input for both device and app sliders in the flyout/full
# mixer. Read the already-cached AppSettings value instead of the previous hard-coded 2.
$sliderPath = 'EarTrumpet/UI/Controls/VolumeSlider.cs'
$slider = Read-SharedStepText $sliderPath
$oldWheel = 'ChangePositionByAmount(Math.Sign(e.Delta) * 2.0);'
$newWheel = 'ChangePositionByAmount(Math.Sign(e.Delta) * (EarTrumpet.App.Settings?.VolumeStep ?? 2));'
if ($slider.Contains($oldWheel)) {
    $slider = $slider.Replace($oldWheel, $newWheel)
} elseif (-not $slider.Contains($newWheel)) {
    throw 'VolumeSlider wheel handler no longer matches the expected source shape.'
}
Write-SharedStepText $sliderPath $slider

# Keep the label short because the current percentage is already shown beside it.
Set-SharedStepResxString 'EarTrumpet/Properties/Resources.resx' 'SettingsVolumeStepText' 'Volume step'
Set-SharedStepResxString 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsVolumeStepText' (ConvertFrom-SharedStepCodePoints @(0x97F3,0x91CF,0x5909,0x66F4,0x5E45))

$mouseVmPath = 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs'
$mouseVm = Read-SharedStepText $mouseVmPath
$volumeStepLinePattern = '(?m)^\s*public string VolumeStepText => Properties\.Resources\.ResourceManager\.GetString\("SettingsVolumeStepText", CultureInfo\.CurrentUICulture\) \?\? ".*?";\s*$'
$volumeStepLineMatches = [regex]::Matches($mouseVm, $volumeStepLinePattern)
if ($volumeStepLineMatches.Count -ne 1) { throw 'VolumeStepText fallback line was not found exactly once.' }
$mouseVm = [regex]::Replace($mouseVm, $volumeStepLinePattern, '        public string VolumeStepText => Properties.Resources.ResourceManager.GetString("SettingsVolumeStepText", CultureInfo.CurrentUICulture) ?? "Volume step";', 1)
Write-SharedStepText $mouseVmPath $mouseVm

# The current percentage is rendered next to the label, so remove the redundant 1%/10%
# endpoint captions beneath the slider while leaving the 1..10 range and snapping intact.
$settingsPath = 'EarTrumpet/UI/Views/SettingsWindow.xaml'
$settings = Read-SharedStepText $settingsPath
$endpointPattern = '(?s)\r?\n\s*<Grid Width="280" Margin="0,2,0,0">\s*<Grid\.ColumnDefinitions>\s*<ColumnDefinition Width="\*" />\s*<ColumnDefinition Width="\*" />\s*</Grid\.ColumnDefinitions>\s*<TextBlock Style="\{StaticResource BodySubText\}" Text="1%" />\s*<TextBlock Grid\.Column="1" HorizontalAlignment="Right" Style="\{StaticResource BodySubText\}" Text="10%" />\s*</Grid>'
$endpointMatches = [regex]::Matches($settings, $endpointPattern)
if ($endpointMatches.Count -eq 1) {
    $settings = [regex]::Replace($settings, $endpointPattern, '', 1)
} elseif ($endpointMatches.Count -gt 1) {
    throw 'More than one volume-step endpoint label block was found.'
} elseif ($settings.Contains('Text="1%"') -or $settings.Contains('Text="10%"')) {
    throw 'Volume-step endpoint labels remain but the expected block shape changed.'
}
Write-SharedStepText $settingsPath $settings

# Behavioral/UI invariants.
$sliderFinal = Read-SharedStepText $sliderPath
if (-not $sliderFinal.Contains($newWheel)) { throw 'In-window wheel handling does not use the configured VolumeStep.' }
if ($sliderFinal.Contains($oldWheel)) { throw 'Hard-coded in-window wheel step remains.' }
$settingsFinal = Read-SharedStepText $settingsPath
if (-not $settingsFinal.Contains('Text="{Binding VolumeStepDisplayText}"')) { throw 'Current volume-step percentage display is missing.' }
if ($settingsFinal.Contains('Text="1%"') -or $settingsFinal.Contains('Text="10%"')) { throw 'Redundant volume-step endpoint labels remain.' }
if (-not (Read-SharedStepText 'EarTrumpet/Properties/Resources.resx').Contains('<value>Volume step</value>')) { throw 'Neutral volume-step label is incorrect.' }
$expectedJa = '<value>' + (ConvertFrom-SharedStepCodePoints @(0x97F3,0x91CF,0x5909,0x66F4,0x5E45)) + '</value>'
if (-not (Read-SharedStepText 'EarTrumpet/Properties/Resources.ja-JP.resx').Contains($expectedJa)) { throw 'Japanese volume-step label is incorrect.' }

Write-Host 'Shared tray/in-window volume step and concise settings UI repair passed.'
