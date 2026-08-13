# Public-release hardening: remove upstream visual branding from the binary payload,
# remove deliberately crashable diagnostics, add a deterministic smoke-test mode,
# and close lifetime/finalizer edge cases found during the pre-public audit.

# Do not redistribute the upstream horn/application icon as MyMix branding. Runtime volume
# glyphs come from Windows; if those system resources are unavailable, use the stock
# SystemIcons.Application fallback instead.
$projectPath = 'EarTrumpet/MyMix.csproj'
$project = Read-Text $projectPath
$project = [regex]::Replace($project, '(?m)^\s*<ApplicationIcon>Assets\\Icon-Light\.ico</ApplicationIcon>\r?\n', '')
$project = [regex]::Replace($project, '(?m)^\s*<Resource Include="Assets\\Icon-(?:Light|Dark)\.ico" />\r?\n', '')
Write-Text $projectPath $project
Remove-Path 'EarTrumpet/Assets/Icon-Light.ico'
Remove-Path 'EarTrumpet/Assets/Icon-Dark.ico'

$appXamlPath = 'EarTrumpet/App.xaml'
$appXaml = Read-Text $appXamlPath
$appXaml = [regex]::Replace($appXaml, '(?m)^\s*<bcl:String x:Key="EarTrumpetIcon(?:Light|Dark)">.*?</bcl:String>\r?\n', '')
Write-Text $appXamlPath $appXaml

Write-Text 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' @'
using EarTrumpet.DataModel;
using EarTrumpet.Interop;
using EarTrumpet.Interop.Helpers;
using EarTrumpet.UI.ViewModels;
using System;
using System.Diagnostics;
using System.Drawing;

namespace EarTrumpet.UI.Helpers
{
    public class TaskbarIconSource : IShellNotifyIconSource
    {
        enum IconKind
        {
            Muted,
            SpeakerZeroBars,
            SpeakerOneBar,
            SpeakerTwoBars,
            SpeakerThreeBars,
            NoDevice,
        }

        public event Action<IShellNotifyIconSource> Changed;
        public Icon Current { get; private set; }

        private readonly DeviceCollectionViewModel _collection;
        private bool _isMouseOver;
        private int? _hash;
        private IconKind _kind;

        public TaskbarIconSource(DeviceCollectionViewModel collection)
        {
            _collection = collection;
            collection.TrayPropertyChanged += OnTrayPropertyChanged;
            OnTrayPropertyChanged();
        }

        public void OnMouseOverChanged(bool isMouseOver)
        {
            _isMouseOver = isMouseOver;
            CheckForUpdate();
        }

        public void CheckForUpdate()
        {
            var nextHash = GetHash();
            if (nextHash == _hash) return;

            _hash = nextHash;
            using (var old = Current)
            {
                Current = SelectAndLoadIcon(_kind);
                Changed?.Invoke(this);
            }
        }

        private void OnTrayPropertyChanged()
        {
            _kind = IconKindFromDeviceCollection(_collection);
            CheckForUpdate();
        }

        private Icon SelectAndLoadIcon(IconKind kind)
        {
            try
            {
                using (var icon = LoadSystemAudioIcon(kind))
                {
                    if (System.Windows.SystemParameters.HighContrast)
                    {
                        return IconHelper.ColorIcon(icon, GetIconFillPercent(kind),
                            _isMouseOver ? System.Windows.SystemColors.HighlightTextColor : System.Windows.SystemColors.WindowTextColor);
                    }
                    if (SystemSettings.IsSystemLightTheme)
                    {
                        return IconHelper.ColorIcon(icon, GetIconFillPercent(kind), System.Windows.Media.Colors.Black);
                    }
                    return (Icon)icon.Clone();
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"TaskbarIconSource system-icon fallback: {ex}");
                return (Icon)SystemIcons.Application.Clone();
            }
        }

        private static Icon LoadSystemAudioIcon(IconKind kind)
        {
            var dpi = WindowsTaskbar.Dpi;
            switch (kind)
            {
                case IconKind.Muted: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.Muted), dpi);
                case IconKind.NoDevice: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.NoDevice), dpi);
                case IconKind.SpeakerZeroBars: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.SpeakerZeroBars), dpi);
                case IconKind.SpeakerOneBar: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.SpeakerOneBar), dpi);
                case IconKind.SpeakerTwoBars: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.SpeakerTwoBars), dpi);
                case IconKind.SpeakerThreeBars: return IconHelper.LoadIconForTaskbar(SndVolSSO.GetPath(SndVolSSO.IconId.SpeakerThreeBars), dpi);
                default: throw new NotImplementedException();
            }
        }

        private int GetHash()
        {
            unchecked
            {
                var hash = (int)_kind;
                hash = (hash * 397) ^ (int)WindowsTaskbar.Dpi;
                hash = (hash * 397) ^ (SystemSettings.IsSystemLightTheme ? 1 : 0);
                hash = (hash * 397) ^ (System.Windows.SystemParameters.HighContrast ? 1 : 0);
                if (System.Windows.SystemParameters.HighContrast) hash = (hash * 397) ^ (_isMouseOver ? 1 : 0);
                return hash;
            }
        }

        private static double GetIconFillPercent(IconKind kind) => kind == IconKind.NoDevice ? 0.4 : 1;

        private static IconKind IconKindFromDeviceCollection(DeviceCollectionViewModel collection)
        {
            if (collection.Default == null) return IconKind.NoDevice;
            switch (collection.Default.IconKind)
            {
                case DeviceViewModel.DeviceIconKind.Mute: return IconKind.Muted;
                case DeviceViewModel.DeviceIconKind.Bar0: return IconKind.SpeakerZeroBars;
                case DeviceViewModel.DeviceIconKind.Bar1: return IconKind.SpeakerOneBar;
                case DeviceViewModel.DeviceIconKind.Bar2: return IconKind.SpeakerTwoBars;
                case DeviceViewModel.DeviceIconKind.Bar3: return IconKind.SpeakerThreeBars;
                default: throw new NotImplementedException();
            }
        }
    }
}
'@

# Remove the hidden Ctrl+Shift intentional crash. Public builds should never expose a
# user-triggerable crash path, even if it originally existed only for diagnostics.
Write-Text 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' @'
using EarTrumpet.Interop.Helpers;
using EarTrumpet.UI.Helpers;
using System;
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
            OpenAboutCommand = new RelayCommand(() => ProcessHelper.StartNoThrow("https://github.com/4i7/MyMix"));
            OpenDiagnosticsCommand = new RelayCommand(() => _openDiagnostics());
        }
    }
}
'@

# Make finalizer cleanup exception-safe. A partially initialized audio session manager must
# never be able to throw from a finalizer and terminate the process.
$sessionCollectionPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionCollection.cs'
$sessionCollection = Read-Text $sessionCollectionPath
$sessionCollection = [regex]::Replace($sessionCollection, '(?ms)        ~AudioDeviceSessionCollection\(\)\s*\{.*?\n        \}(?=\s*private void CreateAndAddSession)', @'
        ~AudioDeviceSessionCollection()
        {
            try
            {
                foreach (var session in _sessions) session.PropertyChanged -= Session_PropertyChanged;
                foreach (var session in _movedSessions) session.PropertyChanged -= MovedSession_PropertyChanged;
                _sessionManager?.UnregisterSessionNotification(this);
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"AudioDeviceSessionCollection cleanup failed: {ex}");
            }
        }
'@)
Write-Text $sessionCollectionPath $sessionCollection

# The view-model optimizer disposes individual device/session VMs. Ensure collection removal
# and Reset paths actually invoke that cleanup before dropping references.
$deviceCollectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$deviceCollection = Read-Text $deviceCollectionPath
$deviceCollection = [regex]::Replace($deviceCollection,
    '(?ms)(if \(allExisting != null\)\s*\{)(?!\s*allExisting\.Dispose\(\);)',
    '$1' + "`r`n                        allExisting.Dispose();")
$deviceCollection = [regex]::Replace($deviceCollection,
    '(?ms)(case NotifyCollectionChangedAction\.Reset:\s*)(?!for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);)',
    '$1' + "for (var i = 0; i < AllDevices.Count; i++) AllDevices[i].Dispose();`r`n                    ")
Write-Text $deviceCollectionPath $deviceCollection

# Give CI a real startup test without colliding with an already-running desktop instance.
$mutexPath = 'EarTrumpet/Interop/Helpers/SingleInstanceAppMutex.cs'
$mutex = Read-Text $mutexPath
if ($mutex -notmatch '(?m)^using System;') {
    $mutex = "using System;`r`n" + $mutex
}
if ($mutex -notmatch 'MYMIX_MUTEX_SUFFIX') {
    $mutexReplacement = @'
$1
            var testSuffix = Environment.GetEnvironmentVariable("MYMIX_MUTEX_SUFFIX");
            if (!string.IsNullOrWhiteSpace(testSuffix)) mutexName += "-" + testSuffix;
'@
    $mutex = [regex]::Replace($mutex,
        '(?m)^(\s*var mutexName = \$"Local\\\\\{assembly\.GetName\(\)\.Name\}-0e510f7b-aed2-40b0-ad72-d2d3fdc89a02";\s*)$',
        $mutexReplacement)
}
Write-Text $mutexPath $mutex

$appPath = 'EarTrumpet/App.xaml.cs'
$app = Read-Text $appPath
if ($app -notmatch '(?m)^using System\.Windows\.Threading;') {
    $app = $app.Replace('using System.Windows.Media;', "using System.Windows.Media;`r`nusing System.Windows.Threading;")
}
if ($app -notmatch '_isSmokeTest') {
    $app = $app.Replace('        private ErrorReporter _errorReporter;', "        private ErrorReporter _errorReporter;`r`n        private bool _isSmokeTest;")
    $startupReplacement = @'
$1
            _isSmokeTest = e.Args.Any(arg => string.Equals(arg, "--smoke-test", StringComparison.OrdinalIgnoreCase));
'@
    $app = [regex]::Replace($app,
        '(?m)^(\s*private void OnAppStartup\(object sender, StartupEventArgs e\)\s*\r?\n\s*\{)',
        $startupReplacement)
    $trayReplacement = @'
$1

            if (_isSmokeTest)
            {
                Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => Shutdown(0)));
            }
'@
    $app = [regex]::Replace($app,
        '(?m)^(\s*_trayIcon\.IsVisible = true;\s*)$',
        $trayReplacement)
}
$app = [regex]::Replace($app, '(?ms)        private bool IsCriticalFontLoadFailure\(Exception ex\)\s*\{.*?\n        \}', @'
        private bool IsCriticalFontLoadFailure(Exception ex)
        {
            var stackTrace = ex?.StackTrace ?? string.Empty;
            return stackTrace.Contains("MS.Internal.Text.TextInterface.FontFamily.GetFirstMatchingFont") ||
                   stackTrace.Contains("MS.Internal.Text.Line.Format");
        }
'@)
Write-Text $appPath $app

# Avoid Path.GetTempFileName() creating a second orphan file before diagnostics are written.
$localDiagPath = 'EarTrumpet/Diagnosis/LocalDataExporter.cs'
$localDiag = Read-Text $localDiagPath
$localDiag = $localDiag.Replace('            var fileName = $"{Path.GetTempFileName()}.txt";', '            var fileName = Path.Combine(Path.GetTempPath(), $"MyMix-diagnostics-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.txt");')
Write-Text $localDiagPath $localDiag

# User-facing resource values should not imply that MyMix is the upstream product or that
# crash reporting exists. Keep internal resource keys intact for compatibility.
foreach ($resourcePath in @('EarTrumpet/Properties/Resources.resx', 'EarTrumpet/Properties/Resources.ja-JP.resx')) {
    $resources = Read-Text $resourcePath
    $resources = [regex]::Replace($resources, '(<value>[^<]*)EarTrumpet([^<]*</value>)', '$1MyMix$2')
    $resources = [regex]::Replace($resources, '(?ms)(<data name="CriticalFailureFontLookupHelpText"[^>]*>\s*<value>).*?(</value>)', '$1A damaged or incompatible font is preventing MyMix from starting. Repair or remove the affected font and try again.$2')
    $resources = [regex]::Replace($resources, '(?ms)(<data name="PrivacyCheckboxText"[^>]*>\s*<value>).*?(</value>)', '$1Crash reporting is disabled in MyMix.$2')
    Write-Text $resourcePath $resources
}

Assert-NotContains $projectPath 'Icon-Light.ico'
Assert-NotContains $projectPath 'Icon-Dark.ico'
Assert-NotContains $appXamlPath 'EarTrumpetIconLight'
Assert-NotContains $appXamlPath 'EarTrumpetIconDark'
Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'IconKind.EarTrumpet'
Assert-Contains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'SystemIcons.Application.Clone()'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'intentional local diagnostic crash'
Assert-Contains $sessionCollectionPath '_sessionManager?.UnregisterSessionNotification(this);'
Assert-Contains $deviceCollectionPath 'allExisting.Dispose();'
Assert-Contains $deviceCollectionPath 'AllDevices[i].Dispose();'
Assert-Contains $mutexPath 'MYMIX_MUTEX_SUFFIX'
Assert-Contains $appPath '--smoke-test'
Assert-Contains $appPath 'DispatcherPriority.ApplicationIdle'
Assert-Contains $localDiagPath 'MyMix-diagnostics-'
Assert-NotContains 'EarTrumpet/Properties/Resources.resx' 'eartrumpet.app/jmp/fixfonts'
