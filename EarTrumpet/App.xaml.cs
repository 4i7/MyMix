using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.Diagnosis;
using EarTrumpet.Extensions;
using EarTrumpet.Interop;
using EarTrumpet.Interop.Helpers;
using EarTrumpet.UI.Helpers;
using EarTrumpet.UI.ViewModels;
using EarTrumpet.UI.Views;
using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace EarTrumpet
{
    public partial class App
    {
        public static bool IsShuttingDown { get; private set; }
        public static bool HasIdentity { get; private set; }
        public static bool HasDevIdentity { get; private set; }
        public static string PackageName { get; private set; }
        public static Version PackageVersion { get; private set; }
        public static TimeSpan Duration => s_appTimer.Elapsed;

        public FlyoutWindow FlyoutWindow { get; private set; }
        public DeviceCollectionViewModel CollectionViewModel { get; private set; }

        private static readonly Stopwatch s_appTimer = Stopwatch.StartNew();
        private FlyoutViewModel _flyoutViewModel;

        private ShellNotifyIcon _trayIcon;
        private WindowHolder _mixerWindow;
        private WindowHolder _settingsWindow;
        private ErrorReporter _errorReporter;
        private bool _isSmokeTest;

        public static AppSettings Settings { get; private set; }

        private void OnAppStartup(object sender, StartupEventArgs e)
        {
            _isSmokeTest = e.Args.Any(arg => string.Equals(arg, "--smoke-test", StringComparison.OrdinalIgnoreCase));

            Exit += (_, __) => IsShuttingDown = true;
            HasIdentity = false;
            HasDevIdentity = false;
            PackageVersion = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            PackageName = null;

            Settings = new AppSettings();
            _errorReporter = new ErrorReporter(Settings);

            if (SingleInstanceAppMutex.TakeExclusivity())
            {
                Exit += (_, __) => SingleInstanceAppMutex.ReleaseExclusivity();

                try
                {
                    ContinueStartup();
                }
                catch (Exception ex) when (IsCriticalFontLoadFailure(ex))
                {
                    ErrorReporter.LogWarning(ex);
                    OnCriticalFontLoadFailure();
                }
            }
            else
            {
                Shutdown();
            }
        }

        private static bool IsStartupRegistrationEnabled()
        {
            const string runKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
            const string valueName = "MyMix";

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(runKeyPath, writable: false))
                {
                    return runKey?.GetValue(valueName) != null;
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"App IsStartupRegistrationEnabled failed: {ex}");
                return false;
            }
        }

        private static void ToggleStartupRegistration()
        {
            SetStartupRegistration(!IsStartupRegistrationEnabled());
        }

        private static void SetStartupRegistration(bool enabled)
        {
            const string runKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
            const string valueName = "MyMix";

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(runKeyPath, writable: true) ?? Registry.CurrentUser.CreateSubKey(runKeyPath))
                {
                    if (runKey == null)
                    {
                        return;
                    }

                    if (enabled)
                    {
                        var executablePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        runKey.SetValue(valueName, $"\"{executablePath}\"");
                    }
                    else
                    {
                        runKey.DeleteValue(valueName, throwOnMissingValue: false);
                    }
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"App SetStartupRegistration failed: {ex}");
            }
        }

        private void ContinueStartup()
        {
            ((UI.Themes.Manager)Resources["ThemeManager"]).Load();

            var deviceManager = WindowsAudioFactory.Create(AudioDeviceKind.Playback);
            deviceManager.Loaded += (_, __) => CompleteStartup();
            CollectionViewModel = new DeviceCollectionViewModel(deviceManager, Settings);

            _trayIcon = new ShellNotifyIcon(new TaskbarIconSource(CollectionViewModel));
            Exit += (_, __) => _trayIcon.IsVisible = false;
            CollectionViewModel.TrayPropertyChanged += () => _trayIcon.SetTooltip(CollectionViewModel.GetTrayToolTip());

            _flyoutViewModel = new FlyoutViewModel(CollectionViewModel, () => _trayIcon.SetFocus(), Settings);
            FlyoutWindow = new FlyoutWindow(_flyoutViewModel);
            // Initialize the FlyoutWindow last because its Show/Hide cycle will pump messages, causing UI frames
            // to be executed, breaking the assumption that startup is complete.
            FlyoutWindow.Initialize();
        }

        private void CompleteStartup()
        {
            _mixerWindow = new WindowHolder(CreateMixerExperience);
            _settingsWindow = new WindowHolder(CreateSettingsExperience);

            Settings.FlyoutHotkeyTyped += () => _flyoutViewModel.OpenFlyout(InputType.Keyboard);
            Settings.MixerHotkeyTyped += () => _mixerWindow.OpenOrClose();
            Settings.SettingsHotkeyTyped += () => _settingsWindow.OpenOrBringToFront();
            Settings.AbsoluteVolumeUpHotkeyTyped += AbsoluteVolumeIncrement;
            Settings.AbsoluteVolumeDownHotkeyTyped += AbsoluteVolumeDecrement;
            Settings.ToggleMuteHotkeyTyped += CollectionViewModel.ToggleDefaultMute;
            Settings.CycleOutputDeviceHotkeyTyped += CollectionViewModel.CycleDefaultDevice;
            Settings.RegisterHotkeys();

            _trayIcon.PrimaryInvoke += (_, type) => _flyoutViewModel.OpenFlyout(type);
            _trayIcon.SecondaryInvoke += (_, args) => _trayIcon.ShowContextMenu(GetTrayContextMenuItems(), args.Point);
            _trayIcon.TertiaryInvoke += (_, __) => CollectionViewModel.ToggleDefaultMute();
            _trayIcon.Scrolled += trayIconScrolled;
            _trayIcon.SetTooltip(CollectionViewModel.GetTrayToolTip());
            _trayIcon.IsVisible = true;

            if (_isSmokeTest)
            {
                Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => Shutdown(0)));
            }
        }

        private void trayIconScrolled(object _, int wheelDelta)
        {
            if (Settings.UseScrollWheelInTray && (!Settings.UseGlobalMouseWheelHook || _flyoutViewModel.State == FlyoutViewState.Hidden))
            {
                var hWndTray = WindowsTaskbar.GetTrayToolbarWindowHwnd();
                var hWndTooltip = User32.SendMessage(hWndTray, User32.TB_GETTOOLTIPS, IntPtr.Zero, IntPtr.Zero);
                User32.SendMessage(hWndTooltip, User32.TTM_POPUP, IntPtr.Zero, IntPtr.Zero);
                
                CollectionViewModel.Default?.IncrementVolume(Math.Sign(wheelDelta) * Settings.VolumeStep);
            }
        }

        private bool IsCriticalFontLoadFailure(Exception ex)
        {
            var stackTrace = ex?.StackTrace ?? string.Empty;
            return stackTrace.Contains("MS.Internal.Text.TextInterface.FontFamily.GetFirstMatchingFont") ||
                   stackTrace.Contains("MS.Internal.Text.Line.Format");
        }

        private void OnCriticalFontLoadFailure()
        {
            Trace.WriteLine($"App OnCriticalFontLoadFailure");

            new Thread(() =>
            {
                if (MessageBox.Show(
                    EarTrumpet.Properties.Resources.CriticalFailureFontLookupHelpText,
                    EarTrumpet.Properties.Resources.CriticalFailureDialogHeaderText,
                    MessageBoxButton.OKCancel,
                    MessageBoxImage.Error,
                    MessageBoxResult.OK) == MessageBoxResult.OK)
                {
                    Trace.WriteLine($"App OnCriticalFontLoadFailure OK");
                }
                Environment.Exit(0);
            }).Start();

            // Stop execution because callbacks to the UI thread will likely cause another cascading font error.
            new AutoResetEvent(false).WaitOne();
        }

        private IEnumerable<ContextMenuItem> GetTrayContextMenuItems()
        {
            var ret = new List<ContextMenuItem>(CollectionViewModel.AllDevices.OrderBy(x => x.DisplayName).Select(dev => new ContextMenuItem
            {
                DisplayName = dev.DisplayName,
                IsChecked = dev.Id == CollectionViewModel.Default?.Id,
                Command = new RelayCommand(() => dev.MakeDefaultDevice()),
            }));

            if (!ret.Any())
            {
                ret.Add(new ContextMenuItem
                {
                    DisplayName = EarTrumpet.Properties.Resources.ContextMenuNoDevices,
                    IsEnabled = false,
                });
            }

            ret.AddRange(new List<ContextMenuItem>
                {
                    new ContextMenuSeparator(),
                    new ContextMenuItem
                    {
                        DisplayName = EarTrumpet.Properties.Resources.WindowsLegacyMenuText,
                        Children = new List<ContextMenuItem>
                        {
                            new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.LegacyVolumeMixerText, Command =  new RelayCommand(LegacyControlPanelHelper.StartLegacyAudioMixer) },
                            new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.PlaybackDevicesText, Command = new RelayCommand(() => LegacyControlPanelHelper.Open("playback")) },
                            new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.RecordingDevicesText, Command = new RelayCommand(() => LegacyControlPanelHelper.Open("recording")) },
                            new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.SoundsControlPanelText, Command = new RelayCommand(() => LegacyControlPanelHelper.Open("sounds")) },
                            new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.OpenSoundSettingsText, Command = new RelayCommand(() => SettingsPageHelper.Open("sound")) },
                            new ContextMenuItem {
                                DisplayName = Environment.OSVersion.IsAtLeast(OSVersions.Windows11) ?
                                    EarTrumpet.Properties.Resources.OpenAppsVolume_Windows11_Text
                                    : EarTrumpet.Properties.Resources.OpenAppsVolume_Windows10_Text, Command = new RelayCommand(() => SettingsPageHelper.Open("apps-volume")) },
                        },
                    },
                    new ContextMenuSeparator(),
                });

            ret.AddRange(new List<ContextMenuItem>
                {
                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.FullWindowTitleText, Command = new RelayCommand(_mixerWindow.OpenOrBringToFront) },
                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.SettingsWindowText, Command = new RelayCommand(_settingsWindow.OpenOrBringToFront) },
                    new ContextMenuItem
                    {
                        DisplayName = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja"
                            ? "Windows サインイン時に MyMix を起動"
                            : "Start MyMix at Windows sign-in",
                        IsChecked = IsStartupRegistrationEnabled(),
                        Command = new RelayCommand(ToggleStartupRegistration),
                    },
                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.ContextMenuExitTitle, Command = new RelayCommand(Shutdown) },
                });
            return ret;
        }

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
        private Window CreateMixerExperience() => new FullWindow { DataContext = new FullWindowViewModel(CollectionViewModel) };

        private void AbsoluteVolumeIncrement()
        {
            foreach (var device in CollectionViewModel.AllDevices.Where(d => !d.IsMuted || d.IsAbsMuted))
            {
                // in any case this device is not abs muted anymore
                device.IsAbsMuted = false;
                device.IncrementVolume(Settings.VolumeStep);
            }
        }

        private void AbsoluteVolumeDecrement()
        {
            foreach (var device in CollectionViewModel.AllDevices.Where(d => !d.IsMuted))
            {
                // if device is not muted but will be muted by 
                bool wasMuted = device.IsMuted;
                // device.IncrementVolume(-2);
                device.Volume -= Settings.VolumeStep;
                // if device is muted by this absolute down
                // .IsMuted is not already updated
                if (!wasMuted == (device.Volume <= 0))
                {
                    device.IsAbsMuted = true;
                }
            }
        }
    }
}
