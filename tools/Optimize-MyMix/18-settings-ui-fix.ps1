# Keep the settings UI deterministic on Windows PowerShell 5.1.
# This stage is intentionally ASCII-only: UTF-8 files without a BOM are parsed as the
# active ANSI code page by Windows PowerShell 5.1, which can corrupt literal Japanese
# text before it is written to the ja-JP resx file.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SettingsFixRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SettingsFixUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-SettingsFixPath([string]$RelativePath) {
    Join-Path $SettingsFixRepoRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-SettingsFixText([string]$RelativePath) {
    $path = Resolve-SettingsFixPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $RelativePath" }
    [IO.File]::ReadAllText($path)
}

function Write-SettingsFixText([string]$RelativePath, [string]$Content) {
    [IO.File]::WriteAllText((Resolve-SettingsFixPath $RelativePath), $Content, $SettingsFixUtf8NoBom)
}

function ConvertFrom-SettingsFixCodePoints([int[]]$CodePoints) {
    -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Set-SettingsFixResxString([string]$RelativePath, [string]$Name, [string]$Value) {
    $text = Read-SettingsFixText $RelativePath
    $escaped = [Security.SecurityElement]::Escape($Value)
    $entry = '  <data name="' + $Name + '" xml:space="preserve">' + "`r`n" +
             '    <value>' + $escaped + '</value>' + "`r`n" +
             '  </data>' + "`r`n"

    $pattern = '(?s)  <data\s+name="' + [regex]::Escape($Name) + '"[^>]*>\s*<value>.*?</value>\s*</data>\r?\n?'
    $rx = New-Object Text.RegularExpressions.Regex($pattern)
    $matches = $rx.Matches($text)
    if ($matches.Count -gt 1) { throw "$RelativePath contains duplicate resource entries for $Name." }

    if ($matches.Count -eq 1) {
        $text = $rx.Replace($text, $entry, 1)
    }
    else {
        if (-not $text.Contains('</root>')) { throw "$RelativePath is not a valid resx document." }
        $text = $text.Replace('</root>', $entry + '</root>')
    }

    Write-SettingsFixText $RelativePath $text
}

$ja = 'EarTrumpet/Properties/Resources.ja-JP.resx'
Set-SettingsFixResxString $ja 'MouseSettingsPageText' (ConvertFrom-SettingsFixCodePoints @(0x30DE, 0x30A6, 0x30B9, 0x8A2D, 0x5B9A))
Set-SettingsFixResxString $ja 'SettingsUseScrollWheelInTray' (ConvertFrom-SettingsFixCodePoints @(0x004D, 0x0079, 0x004D, 0x0069, 0x0078, 0x0020, 0x30A2, 0x30A4, 0x30B3, 0x30F3, 0x4E0A, 0x3067, 0x30B9, 0x30AF, 0x30ED, 0x30FC, 0x30EB, 0x3057, 0x3066, 0x97F3, 0x91CF, 0x3092, 0x5909, 0x66F4))
Set-SettingsFixResxString $ja 'SettingsUseGlobalMouseWheelHook' (ConvertFrom-SettingsFixCodePoints @(0x30D5, 0x30E9, 0x30A4, 0x30A2, 0x30A6, 0x30C8, 0x3092, 0x958B, 0x3044, 0x3066, 0x3044, 0x308B, 0x9593, 0x3001, 0x30B9, 0x30AF, 0x30ED, 0x30FC, 0x30EB, 0x3057, 0x3066, 0x97F3, 0x91CF, 0x3092, 0x5909, 0x66F4))
Set-SettingsFixResxString $ja 'SettingsToggleMuteHotkeyText' (ConvertFrom-SettingsFixCodePoints @(0x65E2, 0x5B9A, 0x306E, 0x51FA, 0x529B, 0x306E, 0x30DF, 0x30E5, 0x30FC, 0x30C8, 0x3092, 0x5207, 0x308A, 0x66FF, 0x3048, 0x308B))
Set-SettingsFixResxString $ja 'SettingsCycleOutputDeviceHotkeyText' (ConvertFrom-SettingsFixCodePoints @(0x6B21, 0x306E, 0x518D, 0x751F, 0x30C7, 0x30D0, 0x30A4, 0x30B9, 0x306B, 0x5207, 0x308A, 0x66FF, 0x3048, 0x308B))
Set-SettingsFixResxString $ja 'SettingsVolumeStepText' (ConvertFrom-SettingsFixCodePoints @(0x97F3, 0x91CF, 0x306E, 0x5909, 0x66F4, 0x5E45, 0x0020, 0x0028, 0x0025, 0x0029))

$settingsPath = 'EarTrumpet/UI/Views/SettingsWindow.xaml'
$settings = Read-SettingsFixText $settingsPath
$comboPattern = '<ComboBox\b(?=[^>]*ItemsSource="\{Binding VolumeStepOptions\}")[^>]*/>'
$comboRx = New-Object Text.RegularExpressions.Regex($comboPattern)
$comboMatches = $comboRx.Matches($settings)
if ($comboMatches.Count -ne 1) { throw "Expected exactly one volume-step ComboBox, found $($comboMatches.Count)." }
$combo = $comboMatches[0].Value
if ($combo -match '\sIsEditable="[^"]*"') {
    $fixedCombo = [regex]::Replace($combo, '\sIsEditable="[^"]*"', ' IsEditable="False"')
}
else {
    $fixedCombo = $combo.Substring(0, $combo.Length - 2).TrimEnd() + ' IsEditable="False" />'
}
$settings = $settings.Substring(0, $comboMatches[0].Index) + $fixedCombo + $settings.Substring($comboMatches[0].Index + $comboMatches[0].Length)
Write-SettingsFixText $settingsPath $settings

$jaText = Read-SettingsFixText $ja
if ($jaText.Contains('Ensure-ResxStringFinal')) { throw 'ja-JP resources still contain a PowerShell parser artifact.' }
foreach ($name in @('MouseSettingsPageText', 'SettingsUseScrollWheelInTray', 'SettingsUseGlobalMouseWheelHook', 'SettingsToggleMuteHotkeyText', 'SettingsCycleOutputDeviceHotkeyText', 'SettingsVolumeStepText')) {
    if (-not $jaText.Contains('<data name="' + $name + '"')) { throw "ja-JP resources are missing $name." }
}
if (-not (Read-SettingsFixText $settingsPath).Contains('ItemsSource="{Binding VolumeStepOptions}" SelectedItem="{Binding VolumeStep, Mode=TwoWay}" IsEditable="False"')) {
    throw 'The volume-step ComboBox is still using the editable search-box presentation.'
}

Write-Host 'Settings UI localization and volume-step presentation repair passed.'
