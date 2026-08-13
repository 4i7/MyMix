param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath([string]$RelativePath) {
    Join-Path $RepoRoot $RelativePath
}

function Read-Text([string]$RelativePath) {
    [IO.File]::ReadAllText((Resolve-RepoPath $RelativePath))
}

function Write-Text([string]$RelativePath, [string]$Content) {
    $path = Resolve-RepoPath $RelativePath
    [IO.File]::WriteAllText($path, $Content, (New-Object Text.UTF8Encoding($false)))
}

# MyMix is intentionally standalone Win32/WPF. Remove the packaged-app storage backend.
Write-Text 'EarTrumpet/DataModel/Storage/StorageFactory.cs' @'
namespace EarTrumpet.DataModel.Storage
{
    public class StorageFactory
    {
        private static readonly ISettingsBag s_globalSettings = new Internal.RegistrySettingsBag();

        public static ISettingsBag GetSettings(string nameSpace = null)
        {
            return (nameSpace == null) ? s_globalSettings :
                new Internal.NamespacedSettingsBag(nameSpace, s_globalSettings);
        }
    }
}
'@

$appPath = 'EarTrumpet/App.xaml.cs'
$app = Read-Text $appPath
$packageInitPattern = '(?ms)^\s*HasIdentity = PackageHelper\.CheckHasIdentity\(\);\s*\r?\n\s*HasDevIdentity = PackageHelper\.HasDevIdentity\(\);\s*\r?\n\s*PackageVersion = PackageHelper\.GetVersion\(HasIdentity\);\s*\r?\n\s*PackageName = PackageHelper\.GetFamilyName\(HasIdentity\);'
$packageInitReplacement = @'
            HasIdentity = false;
            HasDevIdentity = false;
            PackageVersion = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            PackageName = null;
'@
$app2 = [Regex]::Replace($app, $packageInitPattern, $packageInitReplacement)
if ($app2 -eq $app -and $app -match 'PackageHelper\.CheckHasIdentity') {
    throw 'Failed to replace packaged-app initialization in App.xaml.cs.'
}
Write-Text $appPath $app2

$themePath = 'EarTrumpet/UI/Themes/Manager.cs'
$theme = Read-Text $themePath
$theme = $theme -replace '(?m)^using Windows\.UI\.ViewManagement;\r?\n', ''
$animationPattern = '(?ms)\s*if \(Environment\.OSVersion\.IsAtLeast\(OSVersions\.Windows11\)\)\s*\{\s*lastAnimationsEnabledValue = new UISettings\(\)\.AnimationsEnabled;\s*\}\s*else\s*\{\s*// Windows 10 taskbar flyouts are incorrectly tied to \[SPI_GETANIMATION\]\s*// ANIMATIONINFO\.iMinAnimate\s*lastAnimationsEnabledValue = SystemParameters\.MinimizeAnimation;\s*\}'
$theme2 = [Regex]::Replace($theme, $animationPattern, "`r`n                    lastAnimationsEnabledValue = SystemParameters.MinimizeAnimation;")
if ($theme2 -eq $theme -and $theme -match 'new UISettings\(\)') {
    throw 'Failed to remove Windows.UI.ViewManagement from the theme manager.'
}
Write-Text $themePath $theme2

# Telemetry is permanently disabled in MyMix, so remove EarTrumpet's old region-based telemetry default helper and its WinRT globalization dependency.
$settingsPath = 'EarTrumpet/AppSettings.cs'
$settings = Read-Text $settingsPath
$telemetryHelperMarker = '        private bool IsTelemetryEnabledByDefault()'
$helperStart = $settings.IndexOf($telemetryHelperMarker, [StringComparison]::Ordinal)
if ($helperStart -ge 0) {
    $classClose = $settings.LastIndexOf('    }', [StringComparison]::Ordinal)
    if ($classClose -le $helperStart) {
        throw 'Could not locate AppSettings class closing brace while removing telemetry helper.'
    }
    $settings = $settings.Substring(0, $helperStart) + $settings.Substring($classClose)
    Write-Text $settingsPath $settings
}

$projectPath = 'EarTrumpet/MyMix.csproj'
$project = Read-Text $projectPath
$project = [Regex]::Replace(
    $project,
    '(?ms)^\s*<Reference Include="Windows, Version=255\.255\.255\.255, Culture=neutral, processorArchitecture=MSIL">.*?</Reference>\r?\n',
    '')
$project = [Regex]::Replace($project, '(?m)^\s*<Compile Include="DataModel\\Storage\\Internal\\WindowsStorageSettingsBag\.cs" />\r?\n', '')
$project = [Regex]::Replace($project, '(?m)^\s*<Compile Include="Interop\\Helpers\\PackageHelper\.cs" />\r?\n', '')
Write-Text $projectPath $project

Remove-Item -LiteralPath (Resolve-RepoPath 'EarTrumpet/DataModel/Storage/Internal/WindowsStorageSettingsBag.cs') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Resolve-RepoPath 'EarTrumpet/Interop/Helpers/PackageHelper.cs') -Force -ErrorAction SilentlyContinue

# Assert that WinRT package/storage/theme/globalization dependencies are gone from the core application.
$projectCheck = Read-Text $projectPath
if ($projectCheck -match '<Reference Include="Windows,') { throw 'Windows.winmd reference still exists in MyMix.csproj.' }
if ($projectCheck -match 'WindowsStorageSettingsBag|PackageHelper\.cs') { throw 'Packaged-app source files are still compiled.' }
if ((Read-Text $themePath) -match 'Windows\.UI\.ViewManagement|UISettings') { throw 'WinRT UISettings dependency still exists.' }
if ((Read-Text $appPath) -match 'PackageHelper\.') { throw 'PackageHelper is still referenced by App.xaml.cs.' }
if ((Read-Text $settingsPath) -match 'Windows\.Globalization|IsTelemetryEnabledByDefault') { throw 'Legacy telemetry-region WinRT dependency still exists.' }

Write-Host 'Standalone MyMix finalization passed.'
