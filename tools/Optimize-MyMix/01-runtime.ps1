# -----------------------------------------------------------------------------
# 1. Startup/runtime trimming: remove paths MyMix deliberately never activates.
# -----------------------------------------------------------------------------
Replace-RegexOptional 'EarTrumpet/App.xaml' '\s+xmlns:gif="https://github\.com/XamlAnimatedGif/XamlAnimatedGif"\r?\n' ''
Replace-RegexOptional 'EarTrumpet/App.xaml' '\s*<DataTemplate DataType="\{x:Type vm:WelcomeViewModel\}">.*?</DataTemplate>' ''
Replace-RegexOptional 'EarTrumpet/UI/Views/SettingsWindow.xaml' '\s*<DataTemplate DataType="\{x:Type vm:AddonAboutPageViewModel\}">.*?</DataTemplate>' ''

$settingsVmPath = 'EarTrumpet/UI/ViewModels/SettingsViewModel.cs'
$settingsVm = Read-Text $settingsVmPath
$settingsVm = [regex]::Replace($settingsVm,
    '(?ms)\s*if \(value != null && value is AdvertisedCategorySettingsViewModel\)\s*\{.*?\s*return;\s*\}', '')
Write-Text $settingsVmPath $settingsVm

$snapshotPath = 'EarTrumpet/Diagnosis/SnapshotData.cs'
$snapshot = Read-Text $snapshotPath
$snapshot = [regex]::Replace($snapshot, '(?m)^using EarTrumpet\.Extensibility\.Hosting;\r?\n', '')
$snapshot = [regex]::Replace($snapshot, '(?m)^\s*\{ "addons", \(\) => AddonManager\.GetDiagnosticInfo\(\) \},\r?\n', '')
Write-Text $snapshotPath $snapshot

# Release builds have TRACE removed below, so keep diagnostics explicit/local rather than
# maintaining a process-wide circular trace buffer for the entire application lifetime.
Write-Text 'EarTrumpet/Diagnosis/ErrorReporter.cs' @'
using System;
using System.Diagnostics;

namespace EarTrumpet.Diagnosis
{
    class ErrorReporter
    {
        public ErrorReporter(AppSettings settings)
        {
        }

        public void DisplayDiagnosticData()
        {
            LocalDataExporter.DumpAndShowData(null);
        }

        [Conditional("DEBUG")]
        public static void LogWarning(Exception ex)
        {
            Debug.WriteLine($"## Warning ##: {ex}");
        }
    }
}
'@

$appPath = 'EarTrumpet/App.xaml.cs'
$app = Read-Text $appPath
$app = [regex]::Replace($app, '(?m)^\s*RenderOptions\.ProcessRenderMode = RenderMode\.SoftwareOnly;\r?\n', '')
$app = [regex]::Replace($app, '(?ms)\s*#if DEBUG\s*DebugHelpers\.Add\(\);\s*#endif', '')
$app = [regex]::Replace($app, '(?m)^\s*DisplayFirstRunExperience\(\);\r?\n', '')
$app = [regex]::Replace($app, '(?ms)\s*private void DisplayFirstRunExperience\(\)\s*\{.*?\n        \}(?=\s*private bool IsCriticalFontLoadFailure)', "`r`n")
$app = [regex]::Replace($app, '(?m)^\s*ProcessHelper\.StartNoThrow\("https://eartrumpet\.app/jmp/fixfonts"\);\r?\n', '')
Write-Text $appPath $app

$settingsPath = 'EarTrumpet/AppSettings.cs'
$settings = Read-Text $settingsPath
foreach ($property in @('UseLegacyIcon', 'IsTelemetryEnabled', 'UseLogarithmicVolume', 'HasShownFirstRun')) {
    $pattern = '(?ms)\s*public bool ' + [regex]::Escape($property) + '\s*\{.*?\n        \}'
    $settings = [regex]::Replace($settings, $pattern, '')
}
Write-Text $settingsPath @'
using EarTrumpet.DataModel.Storage;
using EarTrumpet.Interop.Helpers;
using System;
using System.Diagnostics;
using static EarTrumpet.Interop.User32;

namespace EarTrumpet
{
    public class AppSettings
    {
        public event Action FlyoutHotkeyTyped;
        public event Action MixerHotkeyTyped;
        public event Action SettingsHotkeyTyped;
        public event Action AbsoluteVolumeUpHotkeyTyped;
        public event Action AbsoluteVolumeDownHotkeyTyped;

        private readonly ISettingsBag _settings = StorageFactory.GetSettings();
        private HotkeyData _flyoutHotkey;
        private HotkeyData _mixerHotkey;
        private HotkeyData _settingsHotkey;
        private HotkeyData _absoluteVolumeUpHotkey;
        private HotkeyData _absoluteVolumeDownHotkey;
        private bool _isExpanded;
        private bool _useScrollWheelInTray;
        private bool _useGlobalMouseWheelHook;
        private WINDOWPLACEMENT? _fullMixerWindowPlacement;
        private WINDOWPLACEMENT? _settingsWindowPlacement;

        public AppSettings()
        {
            // Registry/XML settings are loaded once. Runtime reads are memory-only, which is
            // important for mouse-wheel and flyout paths that can execute frequently.
            _flyoutHotkey = _settings.Get("Hotkey", new HotkeyData());
            _mixerHotkey = _settings.Get("MixerHotkey", new HotkeyData());
            _settingsHotkey = _settings.Get("SettingsHotkey", new HotkeyData());
            _absoluteVolumeUpHotkey = _settings.Get("AbsoluteVolumeUpHotkey", new HotkeyData());
            _absoluteVolumeDownHotkey = _settings.Get("AbsoluteVolumeDownHotkey", new HotkeyData());
            _isExpanded = _settings.Get("IsExpanded", false);
            _useScrollWheelInTray = _settings.Get("UseScrollWheelInTray", true);
            _useGlobalMouseWheelHook = _settings.Get("UseGlobalMouseWheelHook", false);
            _fullMixerWindowPlacement = _settings.Get("FullMixerWindowPlacement", default(WINDOWPLACEMENT?));
            _settingsWindowPlacement = _settings.Get("SettingsWindowPlacement", default(WINDOWPLACEMENT?));
        }

        public void RegisterHotkeys()
        {
            HotkeyManager.Current.Register(_flyoutHotkey);
            HotkeyManager.Current.Register(_mixerHotkey);
            HotkeyManager.Current.Register(_settingsHotkey);
            HotkeyManager.Current.Register(_absoluteVolumeUpHotkey);
            HotkeyManager.Current.Register(_absoluteVolumeDownHotkey);

            HotkeyManager.Current.KeyPressed += hotkey =>
            {
                if (hotkey.Equals(_flyoutHotkey))
                {
                    Trace.WriteLine("AppSettings FlyoutHotkeyTyped");
                    FlyoutHotkeyTyped?.Invoke();
                }
                else if (hotkey.Equals(_settingsHotkey))
                {
                    Trace.WriteLine("AppSettings SettingsHotkeyTyped");
                    SettingsHotkeyTyped?.Invoke();
                }
                else if (hotkey.Equals(_mixerHotkey))
                {
                    Trace.WriteLine("AppSettings MixerHotkeyTyped");
                    MixerHotkeyTyped?.Invoke();
                }
                else if (hotkey.Equals(_absoluteVolumeUpHotkey))
                {
                    Trace.WriteLine("AppSettings AbsoluteVolumeUpHotkeyTyped");
                    AbsoluteVolumeUpHotkeyTyped?.Invoke();
                }
                else if (hotkey.Equals(_absoluteVolumeDownHotkey))
                {
                    Trace.WriteLine("AppSettings AbsoluteVolumeDownHotkeyTyped");
                    AbsoluteVolumeDownHotkeyTyped?.Invoke();
                }
            };
        }

        private void SetHotkey(string key, ref HotkeyData field, HotkeyData value)
        {
            HotkeyManager.Current.Unregister(field);
            field = value ?? new HotkeyData();
            _settings.Set(key, field);
            HotkeyManager.Current.Register(field);
        }

        public HotkeyData FlyoutHotkey
        {
            get => _flyoutHotkey;
            set => SetHotkey("Hotkey", ref _flyoutHotkey, value);
        }

        public HotkeyData MixerHotkey
        {
            get => _mixerHotkey;
            set => SetHotkey("MixerHotkey", ref _mixerHotkey, value);
        }

        public HotkeyData SettingsHotkey
        {
            get => _settingsHotkey;
            set => SetHotkey("SettingsHotkey", ref _settingsHotkey, value);
        }

        public HotkeyData AbsoluteVolumeUpHotkey
        {
            get => _absoluteVolumeUpHotkey;
            set => SetHotkey("AbsoluteVolumeUpHotkey", ref _absoluteVolumeUpHotkey, value);
        }

        public HotkeyData AbsoluteVolumeDownHotkey
        {
            get => _absoluteVolumeDownHotkey;
            set => SetHotkey("AbsoluteVolumeDownHotkey", ref _absoluteVolumeDownHotkey, value);
        }

        public bool IsExpanded
        {
            get => _isExpanded;
            set
            {
                if (_isExpanded == value) return;
                _isExpanded = value;
                _settings.Set("IsExpanded", value);
            }
        }

        public bool UseScrollWheelInTray
        {
            get => _useScrollWheelInTray;
            set
            {
                if (_useScrollWheelInTray == value) return;
                _useScrollWheelInTray = value;
                _settings.Set("UseScrollWheelInTray", value);
            }
        }

        public bool UseGlobalMouseWheelHook
        {
            get => _useGlobalMouseWheelHook;
            set
            {
                if (_useGlobalMouseWheelHook == value) return;
                _useGlobalMouseWheelHook = value;
                _settings.Set("UseGlobalMouseWheelHook", value);
            }
        }

        public WINDOWPLACEMENT? FullMixerWindowPlacement
        {
            get => _fullMixerWindowPlacement;
            set
            {
                _fullMixerWindowPlacement = value;
                _settings.Set("FullMixerWindowPlacement", value);
            }
        }

        public WINDOWPLACEMENT? SettingsWindowPlacement
        {
            get => _settingsWindowPlacement;
            set
            {
                _settingsWindowPlacement = value;
                _settings.Set("SettingsWindowPlacement", value);
            }
        }
    }
}
'@

# Add-on hosting is intentionally absent in MyMix. Keep the core app-move popup, but
# make the add-on surfaces inert and dependency-free.
Write-Text 'EarTrumpet/UI/ViewModels/FocusedDeviceViewModel.cs' @'
using System;
using System.Collections.ObjectModel;

namespace EarTrumpet.UI.ViewModels
{
    class FocusedDeviceViewModel : IFocusedViewModel
    {
        public event Action RequestClose { add { } remove { } }
        public string DisplayName { get; }
        public ObservableCollection<ToolbarItemViewModel> Toolbar { get; } = new ObservableCollection<ToolbarItemViewModel>();
        public ObservableCollection<object> Addons { get; } = new ObservableCollection<object>();
        public bool IsApplicable => false;

        public FocusedDeviceViewModel(DeviceCollectionViewModel mainViewModel, DeviceViewModel device)
        {
            DisplayName = device.DisplayName;
        }

        public void Closing() { }
    }
}
'@

Write-Text 'EarTrumpet/UI/ViewModels/FocusedAppItemViewModel.cs' @'
using EarTrumpet.UI.Helpers;
using System;
using System.Collections.ObjectModel;
using System.Linq;

namespace EarTrumpet.UI.ViewModels
{
    public class FocusedAppItemViewModel : IFocusedViewModel
    {
        public event Action RequestClose;
        public IAppItemViewModel App { get; }
        public ObservableCollection<ToolbarItemViewModel> Toolbar { get; }
        public string DisplayName => App.DisplayName;
        public ObservableCollection<object> Addons { get; } = new ObservableCollection<object>();

        public FocusedAppItemViewModel(DeviceCollectionViewModel parent, IAppItemViewModel app)
        {
            App = app;
            Toolbar = new ObservableCollection<ToolbarItemViewModel>
            {
                new ToolbarItemViewModel
                {
                    GlyphFontSize = 10,
                    DisplayName = Properties.Resources.CloseButtonAccessibleText,
                    Glyph = "\uE8BB",
                    Command = new RelayCommand(() => RequestClose?.Invoke())
                }
            };

            if (app.IsMovable)
            {
                var persistedDeviceId = app.PersistedOutputDevice;
                var items = parent.AllDevices.Select(dev => new ContextMenuItem
                {
                    DisplayName = dev.DisplayName,
                    Command = new RelayCommand(() =>
                    {
                        parent.MoveAppToDevice(app, dev);
                        RequestClose?.Invoke();
                    }),
                    IsChecked = dev.Id == persistedDeviceId,
                }).ToList();

                items.Insert(0, new ContextMenuItem
                {
                    DisplayName = Properties.Resources.DefaultDeviceText,
                    IsChecked = string.IsNullOrWhiteSpace(persistedDeviceId),
                    Command = new RelayCommand(() =>
                    {
                        parent.MoveAppToDevice(app, null);
                        RequestClose?.Invoke();
                    }),
                });
                items.Insert(1, new ContextMenuSeparator());
                Toolbar.Insert(0, new ToolbarItemViewModel
                {
                    GlyphFontSize = 16,
                    DisplayName = Properties.Resources.MoveButtonAccessibleText,
                    Glyph = "\uE8AB",
                    Menu = new ObservableCollection<ContextMenuItem>(items)
                });
            }
        }

        public void Closing() { }
    }
}
'@
