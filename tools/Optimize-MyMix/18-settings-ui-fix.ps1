# Keep the settings UI deterministic on Windows PowerShell 5.1.
# This stage is intentionally ASCII-only: UTF-8 files without a BOM are parsed as the
# active ANSI code page by Windows PowerShell 5.1, which can corrupt literal Japanese
# text before it is written to the ja-JP resx file.
# It is also the final authority for the mouse-settings volume-step presentation.

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

# Accept every integral volume step from 1 through 10. The value remains cached in memory;
# only changing the setting writes storage, while wheel/hotkey reads stay allocation-free.
$appSettingsPath = 'EarTrumpet/AppSettings.cs'
$appSettings = Read-SettingsFixText $appSettingsPath
$normalizePattern = '(?s)        private static int NormalizeVolumeStep\(int value\)\s*\{.*?\r?\n        \}'
$normalizeRx = New-Object Text.RegularExpressions.Regex($normalizePattern)
$normalizeMatches = $normalizeRx.Matches($appSettings)
if ($normalizeMatches.Count -ne 1) { throw "Expected exactly one NormalizeVolumeStep method, found $($normalizeMatches.Count)." }
$normalizeReplacement = @'
        private static int NormalizeVolumeStep(int value)
        {
            if (value < 1) return 1;
            if (value > 10) return 10;
            return value;
        }
'@
$appSettings = $normalizeRx.Replace($appSettings, $normalizeReplacement, 1)
Write-SettingsFixText $appSettingsPath $appSettings

# Slider.Value is a double in WPF. Keep the persisted/runtime value as an int, snap the UI to
# whole percentages, and expose a read-only percentage label without any editable text control.
$mouseVmPath = 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs'
$mouseVm = @'
using System;
using System.Globalization;

namespace EarTrumpet.UI.ViewModels
{
    public class EarTrumpetMouseSettingsPageViewModel : SettingsPageViewModel
    {
        public bool UseScrollWheelInTray { get => _settings.UseScrollWheelInTray; set => _settings.UseScrollWheelInTray = value; }
        public bool UseGlobalMouseWheelHook { get => _settings.UseGlobalMouseWheelHook; set => _settings.UseGlobalMouseWheelHook = value; }
        public double VolumeStep
        {
            get => _settings.VolumeStep;
            set
            {
                _settings.VolumeStep = (int)Math.Round(value, MidpointRounding.AwayFromZero);
                RaisePropertyChanged(nameof(VolumeStep));
                RaisePropertyChanged(nameof(VolumeStepDisplayText));
            }
        }
        public string VolumeStepDisplayText => $"{_settings.VolumeStep}%";
        public string VolumeStepText => Properties.Resources.ResourceManager.GetString("SettingsVolumeStepText", CultureInfo.CurrentUICulture) ?? "Volume step (%)";
        private readonly AppSettings _settings;

        public EarTrumpetMouseSettingsPageViewModel(AppSettings settings) : base(null)
        {
            _settings = settings;
            Title = Properties.Resources.MouseSettingsPageText;
            Glyph = "\xE962";
        }
    }
}
'@
Write-SettingsFixText $mouseVmPath $mouseVm

# A ComboBox in this settings host can inherit presentation pieces from the settings-search
# experience. Remove that route completely: the volume step is a native Slider with integer ticks.
$settingsPath = 'EarTrumpet/UI/Views/SettingsWindow.xaml'
$settings = Read-SettingsFixText $settingsPath
$sliderBinding = 'Value="{Binding VolumeStep, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"'
if (-not $settings.Contains($sliderBinding)) {
    $panelPattern = '(?s)                <StackPanel Margin="0,12,0,0" Orientation="Horizontal">\s*<TextBlock\b(?=[^>]*Text="\{Binding VolumeStepText\}")[^>]*/>\s*<ComboBox\b(?=[^>]*ItemsSource="\{Binding VolumeStepOptions\}")[^>]*/>\s*</StackPanel>'
    $panelRx = New-Object Text.RegularExpressions.Regex($panelPattern)
    $panelMatches = $panelRx.Matches($settings)
    if ($panelMatches.Count -ne 1) { throw "Expected exactly one legacy volume-step panel, found $($panelMatches.Count)." }
    $sliderPanel = @'
                <StackPanel Margin="0,12,0,0" HorizontalAlignment="Left">
                    <Grid Width="280">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        <TextBlock VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding VolumeStepText}" />
                        <TextBlock Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding VolumeStepDisplayText}" />
                    </Grid>
                    <Slider Width="280"
                            Margin="0,8,0,0"
                            Minimum="1"
                            Maximum="10"
                            SmallChange="1"
                            LargeChange="1"
                            TickFrequency="1"
                            IsSnapToTickEnabled="True"
                            IsMoveToPointEnabled="True"
                            AutoToolTipPlacement="TopLeft"
                            AutoToolTipPrecision="0"
                            Value="{Binding VolumeStep, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" />
                    <Grid Width="280" Margin="0,2,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <TextBlock Style="{StaticResource BodySubText}" Text="1%" />
                        <TextBlock Grid.Column="1" HorizontalAlignment="Right" Style="{StaticResource BodySubText}" Text="10%" />
                    </Grid>
                </StackPanel>
'@
    $settings = $panelRx.Replace($settings, $sliderPanel.TrimEnd("`r", "`n"), 1)
}
Write-SettingsFixText $settingsPath $settings

# Final checks deliberately reject the old ComboBox/options path so the search placeholder can
# never become the volume-step content again.
$jaText = Read-SettingsFixText $ja
if ($jaText.Contains('Ensure-ResxStringFinal')) { throw 'ja-JP resources still contain a PowerShell parser artifact.' }
foreach ($name in @('MouseSettingsPageText', 'SettingsUseScrollWheelInTray', 'SettingsUseGlobalMouseWheelHook', 'SettingsToggleMuteHotkeyText', 'SettingsCycleOutputDeviceHotkeyText', 'SettingsVolumeStepText')) {
    if (-not $jaText.Contains('<data name="' + $name + '"')) { throw "ja-JP resources are missing $name." }
}

$appSettingsFinal = Read-SettingsFixText $appSettingsPath
if (-not $appSettingsFinal.Contains('if (value < 1) return 1;') -or -not $appSettingsFinal.Contains('if (value > 10) return 10;')) {
    throw 'VolumeStep is not clamped to the 1..10 range.'
}
$mouseVmFinal = Read-SettingsFixText $mouseVmPath
if ($mouseVmFinal.Contains('VolumeStepOptions')) { throw 'Legacy volume-step options remain in the mouse settings view model.' }
if (-not $mouseVmFinal.Contains('public double VolumeStep')) { throw 'Slider-compatible VolumeStep property is missing.' }
if (-not $mouseVmFinal.Contains('VolumeStepDisplayText')) { throw 'Volume-step percentage display is missing.' }

$settingsFinal = Read-SettingsFixText $settingsPath
if ($settingsFinal.Contains('ItemsSource="{Binding VolumeStepOptions}"')) { throw 'Legacy volume-step ComboBox remains in SettingsWindow.xaml.' }
foreach ($needle in @('<Slider Width="280"','Minimum="1"','Maximum="10"','TickFrequency="1"','IsSnapToTickEnabled="True"',$sliderBinding)) {
    if (-not $settingsFinal.Contains($needle)) { throw "Volume-step slider is missing required invariant: $needle" }
}
[xml]$settingsFinal | Out-Null

Write-Host 'Settings UI localization and 1-10 percent volume-step slider repair passed.'
