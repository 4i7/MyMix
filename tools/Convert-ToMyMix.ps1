#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Archive = "EarTrumpet-master.zip",
    [switch]$KeepArchive,
    [switch]$SkipBuild,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Marker = Join-Path $Root ".mymix-converted"
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

function Replace-Literal([string]$RelativePath, [string]$Old, [string]$New) {
    $text = Read-Text $RelativePath
    if (-not $text.Contains($Old)) {
        throw "Expected text not found in $RelativePath`n--- expected ---`n$Old"
    }
    Write-Text $RelativePath ($text.Replace($Old, $New))
}

function Replace-Regex([string]$RelativePath, [string]$Pattern, [string]$Replacement, [int]$MinimumMatches = 1) {
    $text = Read-Text $RelativePath
    $matches = [regex]::Matches($text, $Pattern, $RegexSingleline)
    if ($matches.Count -lt $MinimumMatches) {
        throw "Expected pattern not found in $RelativePath`n$Pattern"
    }
    Write-Text $RelativePath ([regex]::Replace($text, $Pattern, $Replacement, $RegexSingleline))
}

function Remove-Regex([string]$RelativePath, [string]$Pattern, [int]$MinimumMatches = 1) {
    Replace-Regex $RelativePath $Pattern "" $MinimumMatches
}

function Replace-ResourceValues([string]$RelativePath) {
    $text = Read-Text $RelativePath
    $updated = [regex]::Replace(
        $text,
        '<value>(.*?)</value>',
        { param($m) '<value>' + $m.Groups[1].Value.Replace('EarTrumpet', 'MyMix') + '</value>' },
        $RegexSingleline)
    Write-Text $RelativePath $updated
}

function Extract-UpstreamSource {
    if (Test-Path -LiteralPath (Resolve-RepoPath "EarTrumpet/App.xaml.cs")) {
        return
    }

    $archivePath = Resolve-RepoPath $Archive
    if (-not (Test-Path -LiteralPath $archivePath)) {
        throw "Source archive not found: $Archive"
    }

    $temp = Join-Path $Root ".mymix-extract"
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $archivePath -DestinationPath $temp -Force

    $sourceRoot = Get-ChildItem -LiteralPath $temp -Directory | Select-Object -First 1
    if ($null -eq $sourceRoot) {
        throw "The source archive did not contain a top-level directory."
    }

    $upstreamReadme = Join-Path $sourceRoot.FullName "README.md"
    if (Test-Path -LiteralPath $upstreamReadme) {
        Copy-Item -LiteralPath $upstreamReadme -Destination (Resolve-RepoPath "UPSTREAM_README.md") -Force
    }

    foreach ($item in Get-ChildItem -LiteralPath $sourceRoot.FullName -Force) {
        if ($item.Name -in @('.git', '.github', 'README.md')) {
            continue
        }
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Root $item.Name) -Recurse -Force
    }

    Remove-Item -LiteralPath $temp -Recurse -Force
}

function Convert-UiLayout {
    foreach ($file in @('EarTrumpet/UI/Views/AppItemView.xaml', 'EarTrumpet/UI/Views/DeviceView.xaml')) {
        Remove-Regex $file '\s*<ColumnDefinition Width="\{DynamicResource Mutable_VolumeCellWidth\}" />'
        Remove-Regex $file '\s*<TextBlock Grid.Column="2"(?:[^>]*/>|.*?</TextBlock>)'
        Replace-Literal $file '<ctl:VolumeSlider Grid.Column="1"' '<ctl:VolumeSlider Grid.Column="1" Margin="0,0,16,0"'
    }
    Remove-Regex 'EarTrumpet/UI/Mutable.xaml' '\s*<win:GridLength x:Key="Mutable_VolumeCellWidth">.*?</win:GridLength>'
}

function Convert-PrivacyAndDiagnostics {
    Replace-Regex 'EarTrumpet/AppSettings.cs' 'public bool IsTelemetryEnabled\s*\{.*?\n        \}' @'
public bool IsTelemetryEnabled
        {
            get => false;
            set { }
        }
'@

    Write-Text 'EarTrumpet/Diagnosis/ErrorReporter.cs' @'
using System;
using System.Diagnostics;

namespace EarTrumpet.Diagnosis
{
    class ErrorReporter
    {
        private readonly CircularBufferTraceListener _listener;

        public ErrorReporter(AppSettings settings)
        {
            _listener = new CircularBufferTraceListener();
            Trace.Listeners.Clear();
            Trace.Listeners.Add(_listener);
        }

        public void DisplayDiagnosticData()
        {
            LocalDataExporter.DumpAndShowData(_listener.GetLogText());
        }

        public static void LogWarning(Exception ex)
        {
            Trace.WriteLine($"## Warning ##: {ex}");
        }
    }
}
'@

    Remove-Regex 'EarTrumpet/App.config' '\s*<configSections>.*?</configSections>'
    Remove-Regex 'EarTrumpet/App.config' '\s*<bugsnag .*?/>'
    Remove-Regex 'EarTrumpet/packages.config' '\s*<package id="Bugsnag" .*?/>'
    Remove-Regex 'EarTrumpet/packages.config' '\s*<package id="Bugsnag.ConfigurationSection" .*?/>'
    Remove-Regex 'EarTrumpet/EarTrumpet.csproj' '\s*<Reference Include="Bugsnag,.*?</Reference>'
    Remove-Regex 'EarTrumpet/EarTrumpet.csproj' '\s*<Reference Include="Bugsnag.ConfigurationSection,.*?</Reference>'

    Write-Text 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' @'
using EarTrumpet.Interop.Helpers;
using EarTrumpet.UI.Helpers;
using System;
using System.Diagnostics;
using System.Windows.Input;

namespace EarTrumpet.UI.ViewModels
{
    class EarTrumpetAboutPageViewModel : SettingsPageViewModel
    {
        public ICommand OpenDiagnosticsCommand { get; }
        public ICommand OpenAboutCommand { get; }
        public string AboutText { get; }

        private readonly Action _openDiagnostics;

        public EarTrumpetAboutPageViewModel(Action openDiagnostics) : base(null)
        {
            _openDiagnostics = openDiagnostics;
            Glyph = "\xE946";
            Title = Properties.Resources.AboutTitle;
            AboutText = $"MyMix {App.PackageVersion}";
            OpenAboutCommand = new RelayCommand(OpenAbout);
            OpenDiagnosticsCommand = new RelayCommand(OpenDiagnostics);
        }

        private void OpenDiagnostics()
        {
            if (Keyboard.IsKeyDown(Key.LeftShift) && Keyboard.IsKeyDown(Key.LeftCtrl))
            {
                Trace.WriteLine("EarTrumpetAboutPageViewModel OpenDiagnostics - CRASH");
                throw new Exception("This is an intentional local diagnostic crash.");
            }
            _openDiagnostics.Invoke();
        }

        private void OpenAbout() => ProcessHelper.StartNoThrow("https://github.com/4i7/MyMix");
    }
}
'@

    $aboutTemplate = @'
        <DataTemplate DataType="{x:Type vm:EarTrumpetAboutPageViewModel}">
            <StackPanel>
                <StackPanel Margin="12,24" Orientation="Horizontal">
                    <TextBlock FontSize="24" Text="MyMix" />
                </StackPanel>
                <TextBlock VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding AboutText}" />
                <TextBlock VerticalAlignment="Center"
                           Style="{StaticResource BodySubText}"
                           Text="Based on EarTrumpet. See LICENSE for upstream copyright and license terms." />
                <TextBlock Style="{StaticResource HyperlinkBlock}">
                    <Hyperlink Command="{Binding OpenAboutCommand}"><Run Text="MyMix repository" /></Hyperlink>
                </TextBlock>
                <TextBlock Style="{StaticResource HyperlinkBlock}">
                    <Hyperlink Command="{Binding OpenDiagnosticsCommand}"><Run Text="Show local diagnostics" /></Hyperlink>
                </TextBlock>
            </StackPanel>
        </DataTemplate>
'@
    Replace-Regex 'EarTrumpet/UI/Views/SettingsWindow.xaml' '<DataTemplate DataType="\{x:Type vm:EarTrumpetAboutPageViewModel\}">.*?</DataTemplate>' $aboutTemplate
    Remove-Regex 'EarTrumpet/UI/Views/SettingsWindow.xaml' '\s*<DataTemplate DataType="\{x:Type vm:EarTrumpetCommunitySettingsPageViewModel\}">.*?</DataTemplate>'
    Remove-Regex 'EarTrumpet/UI/Views/SettingsWindow.xaml' '\s*<DataTemplate DataType="\{x:Type vm:EarTrumpetLegacySettingsPageViewModel\}">.*?</DataTemplate>'
}

function Convert-LegacyIcon {
    Remove-Regex 'EarTrumpet/AppSettings.cs' '\s*public event EventHandler<bool> UseLegacyIconChanged;'
    Replace-Regex 'EarTrumpet/AppSettings.cs' 'public bool UseLegacyIcon\s*\{.*?\n        \}' @'
public bool UseLegacyIcon
        {
            get => false;
            set { }
        }
'@

    $file = 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs'
    $taskbar = Read-Text $file
    $taskbar = [regex]::Replace($taskbar, '\s*private readonly AppSettings _settings;', '')
    $taskbar = $taskbar.Replace('public TaskbarIconSource(DeviceCollectionViewModel collection, AppSettings settings)', 'public TaskbarIconSource(DeviceCollectionViewModel collection)')
    $taskbar = [regex]::Replace($taskbar, '\s*_settings = settings;', '')
    $taskbar = [regex]::Replace($taskbar, '\s*_settings\.UseLegacyIconChanged \+= \(_, __\) => CheckForUpdate\(\);', '')
    $taskbar = [regex]::Replace($taskbar, '\s*if \(_settings\.UseLegacyIcon\)\s*\{\s*kind = IconKind\.EarTrumpet;\s*\}', '')
    $taskbar = [regex]::Replace(
        $taskbar,
        'private string GetHash\(\) =>.*?;',
        @'
private string GetHash() =>
            $"kind={_kind} " +
            $"{(System.Windows.SystemParameters.HighContrast ? $"hc=true mouse={_isMouseOver} " : "")}" +
            $"dpi={WindowsTaskbar.Dpi} " +
            $"isSysLight={SystemSettings.IsSystemLightTheme}";
'@,
        $RegexSingleline)
    Write-Text $file $taskbar

    Replace-Literal 'EarTrumpet/App.xaml.cs' 'new TaskbarIconSource(CollectionViewModel, Settings)' 'new TaskbarIconSource(CollectionViewModel)'
}

function Convert-LogarithmicVolume {
    Replace-Regex 'EarTrumpet/AppSettings.cs' 'public bool UseLogarithmicVolume\s*\{.*?\n        \}' @'
public bool UseLogarithmicVolume
        {
            get => true;
            set { }
        }
'@

    foreach ($file in @(
        'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs',
        'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs',
        'EarTrumpet/DataModel/Audio/Mocks/AudioDevice.cs',
        'EarTrumpet/DataModel/Audio/Mocks/AudioDeviceSession.cs'
    )) {
        Replace-Regex $file 'get\s*\{\s*return App\.Settings\.UseLogarithmicVolume \? _volume\.ToDisplayVolume\(\) : _volume;\s*\}' 'get => _volume.ToDisplayVolume();'
        Replace-Regex $file '\s*if \(App\.Settings\.UseLogarithmicVolume\)\s*\{\s*value = value\.ToLogVolume\(\);\s*\}' "`r`n                value = value.ToLogVolume();"
    }

    foreach ($file in @(
        'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs',
        'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs'
    )) {
        Replace-Regex $file 'IsMuted = App\.Settings\.UseLogarithmicVolume \? _volume <= \(1 / 100f\)\.ToLogVolume\(\) : _volume\.ToVolumeInt\(\) == 0;' 'IsMuted = _volume <= (1 / 100f).ToLogVolume();'
    }

    Write-Text 'EarTrumpet/Extensions/FloatExtensions.cs' @'
using System;

namespace EarTrumpet.Extensions
{
    public static class FloatExtensions
    {
        private const double CurveFactor = 5.757;
        private static readonly double InverseCurveScale = Math.Exp(-CurveFactor);

        public static int ToVolumeInt(this float val)
        {
            return Convert.ToInt32(Math.Round(val * 100, MidpointRounding.AwayFromZero));
        }

        public static float Bound(this float val, float min, float max)
        {
            return Math.Max(min, Math.Min(max, val));
        }

        public static float ToLogVolume(this float val)
        {
            return ((float)(Math.Exp(CurveFactor * val) * InverseCurveScale)).Bound(0, 1f);
        }

        public static float ToDisplayVolume(this float val)
        {
            if (val <= 0)
            {
                return 0;
            }
            return ((float)((Math.Log(val) + CurveFactor) / CurveFactor)).Bound(0, 1f);
        }
    }
}
'@
}

function Convert-CoreRuntime {
    Remove-Regex 'EarTrumpet/App.xaml.cs' '\s*using EarTrumpet\.Extensibility;'
    Remove-Regex 'EarTrumpet/App.xaml.cs' '\s*using EarTrumpet\.Extensibility\.Hosting;'
    Remove-Regex 'EarTrumpet/App.xaml.cs' '\s*AddonManager\.Load\(shouldLoadInternalAddons: HasDevIdentity\);'
    Remove-Regex 'EarTrumpet/App.xaml.cs' '\s*Exit \+= \(_, __\) => AddonManager\.Shutdown\(\);'
    Remove-Regex 'EarTrumpet/App.xaml.cs' '\s*var addonItems = AddonManager\.Host\.TrayContextMenuItems.*?ret\.Add\(new ContextMenuSeparator\(\)\);\s*\}'

    $settingsMethod = @'
        private Window CreateSettingsExperience()
        {
            var defaultCategory = new SettingsCategoryViewModel(
                EarTrumpet.Properties.Resources.SettingsCategoryTitle,
                "\xE71D",
                EarTrumpet.Properties.Resources.SettingsDescriptionText,
                null,
                new SettingsPageViewModel[]
                    {
                        new EarTrumpetShortcutsPageViewModel(Settings),
                        new EarTrumpetMouseSettingsPageViewModel(Settings),
                        new EarTrumpetAboutPageViewModel(() => _errorReporter.DisplayDiagnosticData())
                    });

            var allCategories = new List<SettingsCategoryViewModel> { defaultCategory };
            var viewModel = new SettingsViewModel(EarTrumpet.Properties.Resources.SettingsWindowText, allCategories);
            return new SettingsWindow { DataContext = viewModel };
        }

'@
    Replace-Regex 'EarTrumpet/App.xaml.cs' '        private Window CreateSettingsExperience\(\).*?(?=        private Window CreateMixerExperience\(\))' $settingsMethod

    $firstRun = @'
        private void DisplayFirstRunExperience()
        {
            if (!Settings.HasShownFirstRun)
            {
                Settings.HasShownFirstRun = true;
            }
        }

'@
    Replace-Regex 'EarTrumpet/App.xaml.cs' '        private void DisplayFirstRunExperience\(\).*?(?=        private bool IsCriticalFontLoadFailure)' $firstRun
    Replace-Literal 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' '@"Software\EarTrumpet"' '@"Software\MyMix"'
}

function Convert-Branding {
    Get-ChildItem -LiteralPath (Resolve-RepoPath 'EarTrumpet/Properties') -Filter 'Resources*.resx' | ForEach-Object {
        Replace-ResourceValues ('EarTrumpet/Properties/' + $_.Name)
    }

    Replace-Literal 'EarTrumpet/EarTrumpet.csproj' '<AssemblyName>EarTrumpet</AssemblyName>' '<AssemblyName>MyMix</AssemblyName>'
    Replace-Literal 'EarTrumpet/App.xaml' 'pack://application:,,,/EarTrumpet;component/Assets/Icon-Light.ico' 'pack://application:,,,/MyMix;component/Assets/Icon-Light.ico'
    Replace-Literal 'EarTrumpet/App.xaml' 'pack://application:,,,/EarTrumpet;component/Assets/Icon-Dark.ico' 'pack://application:,,,/MyMix;component/Assets/Icon-Dark.ico'

    $assemblyInfo = Read-Text 'EarTrumpet/Properties/AssemblyInfo.cs'
    $assemblyInfo = $assemblyInfo.Replace('AssemblyTitle("EarTrumpet")', 'AssemblyTitle("MyMix")')
    $assemblyInfo = $assemblyInfo.Replace('AssemblyProduct("EarTrumpet")', 'AssemblyProduct("MyMix")')
    $assemblyInfo = $assemblyInfo.Replace('AssemblyCompany("File-New-Project")', 'AssemblyCompany("4i7")')
    Write-Text 'EarTrumpet/Properties/AssemblyInfo.cs' $assemblyInfo

    $oldProject = Resolve-RepoPath 'EarTrumpet/EarTrumpet.csproj'
    $newProject = Resolve-RepoPath 'EarTrumpet/MyMix.csproj'
    Move-Item -LiteralPath $oldProject -Destination $newProject -Force

    $solution = Read-Text 'EarTrumpet.vs15.sln'
    $solution = $solution.Replace('= "EarTrumpet", "EarTrumpet\EarTrumpet.csproj"', '= "MyMix", "EarTrumpet\MyMix.csproj"')
    $solution = $solution.Replace('= "EarTrumpet.Package", "EarTrumpet.Package\EarTrumpet.Package.wapproj"', '= "MyMix.Package", "EarTrumpet.Package\MyMix.Package.wapproj"')
    $solution = [regex]::Replace($solution, 'Project\("\{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC\}"\) = "EarTrumpet\.ColorTool".*?EndProject\r?\n', '', $RegexSingleline)
    $solution = [regex]::Replace($solution, '^\s*\{E5B2C3B5-4CED-4C82-8A82-D290A7E0FC5D\}.*?\r?\n', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    Write-Text 'MyMix.sln' $solution
    Remove-Item -LiteralPath (Resolve-RepoPath 'EarTrumpet.vs15.sln') -Force

    $oldWap = Resolve-RepoPath 'EarTrumpet.Package/EarTrumpet.Package.wapproj'
    $newWap = Resolve-RepoPath 'EarTrumpet.Package/MyMix.Package.wapproj'
    $wap = [IO.File]::ReadAllText($oldWap)
    $wap = $wap.Replace('..\EarTrumpet\EarTrumpet.csproj', '..\EarTrumpet\MyMix.csproj')
    [IO.File]::WriteAllText($newWap, $wap, $Utf8NoBom)
    Remove-Item -LiteralPath $oldWap -Force

    $manifest = Read-Text 'EarTrumpet.Package/Package.appxmanifest'
    $manifest = $manifest.Replace('Identity Name="40459File-New-Project.EarTrumpet"', 'Identity Name="4i7.MyMix"')
    $manifest = $manifest.Replace('<DisplayName>EarTrumpet</DisplayName>', '<DisplayName>MyMix</DisplayName>')
    $manifest = $manifest.Replace('<PublisherDisplayName>File-New-Project</PublisherDisplayName>', '<PublisherDisplayName>4i7</PublisherDisplayName>')
    $manifest = $manifest.Replace('<Application Id="EarTrumpet"', '<Application Id="MyMix"')
    $manifest = $manifest.Replace('DisplayName="EarTrumpet" Description="EarTrumpet"', 'DisplayName="MyMix" Description="MyMix"')
    $manifest = $manifest.Replace('Executable="EarTrumpet\EarTrumpet.exe"', 'Executable="EarTrumpet\MyMix.exe"')
    $manifest = $manifest.Replace('<desktop:StartupTask TaskId="EarTrumpet" Enabled="true" DisplayName="EarTrumpet" />', '<desktop:StartupTask TaskId="MyMix" Enabled="true" DisplayName="MyMix" />')
    Write-Text 'EarTrumpet.Package/Package.appxmanifest' $manifest

    foreach ($path in @('.azure-pipelines.yml', 'crowdin.yml')) {
        Remove-Item -LiteralPath (Resolve-RepoPath $path) -Force -ErrorAction SilentlyContinue
    }
}

function Write-MyMixReadme {
    Write-Text 'README.md' @'
# MyMix

MyMix is a private Windows volume mixer derived from EarTrumpet and optimized around a single logarithmic volume-control path.

## MyMix changes

- Removes the numeric volume labels at the right side of device/app rows and gives that width back to the slider with a 16 px right inset.
- Uses logarithmic volume mapping unconditionally; the linear/logarithmic runtime branch and settings toggle are no longer part of the hot path.
- Removes outbound Bugsnag crash reporting and the EarTrumpet feedback/telemetry UI. Diagnostics are local-only.
- Removes the legacy EarTrumpet-icon selection feature from the tray-icon path.
- Disables add-on-host startup and removes community/legacy settings pages from the core experience.
- Uses a separate MyMix assembly name, package identity, startup task, mutex identity (via assembly name), and unpackaged registry key.
- Keeps upstream internal namespaces where renaming them would add risk without changing the product identity.

## Build

Run `tools\Convert-ToMyMix.ps1` once from PowerShell on Windows. The main solution after conversion is `MyMix.sln` and the application project is `EarTrumpet\MyMix.csproj`.

## Privacy

MyMix does not initialize Bugsnag and does not transmit crash/diagnostic data to the EarTrumpet project. The diagnostics command writes and opens a local text file only.

## License and attribution

MyMix is based on EarTrumpet. The upstream `LICENSE` is retained and applies to the derived source. `UPSTREAM_README.md` contains the upstream project README captured from the source archive.
'@
}

function Invoke-Validation {
    $validator = Resolve-RepoPath 'tools/Test-MyMixRefactor.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator
    if ($LASTEXITCODE -ne 0) {
        throw "MyMix refactor validation failed."
    }
}

function Invoke-Build {
    if ($SkipBuild) { return }

    $nuget = Get-Command nuget.exe -ErrorAction SilentlyContinue
    if ($nuget) {
        & $nuget.Source restore (Resolve-RepoPath 'MyMix.sln')
        if ($LASTEXITCODE -ne 0) { throw "NuGet restore failed." }
    }
    else {
        Write-Warning "nuget.exe was not found; package restore was skipped."
    }

    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($msbuild) {
        & $msbuild.Source (Resolve-RepoPath 'MyMix.sln') /m /p:Configuration=Release /p:Platform=x86
        if ($LASTEXITCODE -ne 0) { throw "MSBuild failed." }
    }
    else {
        Write-Warning "msbuild.exe was not found; build validation was skipped. Use a Visual Studio Developer PowerShell to build MyMix.sln."
    }
}

if ((Test-Path -LiteralPath $Marker) -and -not $Force) {
    Write-Host "MyMix conversion marker already exists."
    Invoke-Validation
    Invoke-Build
    exit 0
}

Extract-UpstreamSource
Convert-UiLayout
Convert-PrivacyAndDiagnostics
Convert-LegacyIcon
Convert-LogarithmicVolume
Convert-CoreRuntime
Convert-Branding
Write-MyMixReadme

if (-not $KeepArchive) {
    Remove-Item -LiteralPath (Resolve-RepoPath $Archive) -Force -ErrorAction SilentlyContinue
}

Write-Text '.mymix-converted' "upstream=File-New-Project/EarTrumpet@aa894e51c22f5f9a939b31b224c4d2d3e163416e`nconverted=$(Get-Date -Format o)`n"
Invoke-Validation
Invoke-Build
Write-Host "MyMix conversion complete."
