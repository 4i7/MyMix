# Final low-overhead control stage. Runs after runtime-stability so an upstream refresh cannot
# reintroduce periodic process polling or hard-coded volume steps.

function Ensure-ResxStringFinal([string]$RelativePath, [string]$Name, [string]$Value) {
    $text = Read-Text $RelativePath
    $needle = '<data name="' + $Name + '"'
    if ($text.Contains($needle)) { return }
    $escaped = [Security.SecurityElement]::Escape($Value)
    $entry = '  <data name="' + $Name + '" xml:space="preserve">' + "`r`n" +
             '    <value>' + $escaped + '</value>' + "`r`n" +
             '  </data>' + "`r`n"
    if (-not $text.Contains('</root>')) { throw ($RelativePath + ' is not a valid resx document.') }
    Write-Text $RelativePath ($text.Replace('</root>', $entry + '</root>'))
}

# Canonical settings implementation: RegisterHotKey remains the event source and all runtime
# preferences are cached in fields, so hot paths never touch registry/XML storage.
Write-Text 'EarTrumpet/AppSettings.cs' @'
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
        public event Action ToggleMuteHotkeyTyped;
        public event Action CycleOutputDeviceHotkeyTyped;

        private readonly ISettingsBag _settings = StorageFactory.GetSettings();
        private HotkeyData _flyoutHotkey;
        private HotkeyData _mixerHotkey;
        private HotkeyData _settingsHotkey;
        private HotkeyData _absoluteVolumeUpHotkey;
        private HotkeyData _absoluteVolumeDownHotkey;
        private HotkeyData _toggleMuteHotkey;
        private HotkeyData _cycleOutputDeviceHotkey;
        private bool _isExpanded;
        private bool _useScrollWheelInTray;
        private bool _useGlobalMouseWheelHook;
        private int _volumeStep;
        private WINDOWPLACEMENT? _fullMixerWindowPlacement;
        private WINDOWPLACEMENT? _settingsWindowPlacement;

        public AppSettings()
        {
            // Registry/XML settings are loaded once. Runtime reads are memory-only, which is
            // important for mouse-wheel, hotkey, and flyout paths that can execute frequently.
            _flyoutHotkey = _settings.Get("Hotkey", new HotkeyData());
            _mixerHotkey = _settings.Get("MixerHotkey", new HotkeyData());
            _settingsHotkey = _settings.Get("SettingsHotkey", new HotkeyData());
            _absoluteVolumeUpHotkey = _settings.Get("AbsoluteVolumeUpHotkey", new HotkeyData());
            _absoluteVolumeDownHotkey = _settings.Get("AbsoluteVolumeDownHotkey", new HotkeyData());
            _toggleMuteHotkey = _settings.Get("ToggleMuteHotkey", new HotkeyData());
            _cycleOutputDeviceHotkey = _settings.Get("CycleOutputDeviceHotkey", new HotkeyData());
            _isExpanded = _settings.Get("IsExpanded", false);
            _useScrollWheelInTray = _settings.Get("UseScrollWheelInTray", true);
            _useGlobalMouseWheelHook = _settings.Get("UseGlobalMouseWheelHook", false);
            _volumeStep = NormalizeVolumeStep(_settings.Get("VolumeStep", 2));
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
            HotkeyManager.Current.Register(_toggleMuteHotkey);
            HotkeyManager.Current.Register(_cycleOutputDeviceHotkey);

            HotkeyManager.Current.KeyPressed += hotkey =>
            {
                if (hotkey.Equals(_flyoutHotkey)) FlyoutHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_settingsHotkey)) SettingsHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_mixerHotkey)) MixerHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_absoluteVolumeUpHotkey)) AbsoluteVolumeUpHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_absoluteVolumeDownHotkey)) AbsoluteVolumeDownHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_toggleMuteHotkey)) ToggleMuteHotkeyTyped?.Invoke();
                else if (hotkey.Equals(_cycleOutputDeviceHotkey)) CycleOutputDeviceHotkeyTyped?.Invoke();
            };
        }

        private void SetHotkey(string key, ref HotkeyData field, HotkeyData value)
        {
            HotkeyManager.Current.Unregister(field);
            field = value ?? new HotkeyData();
            _settings.Set(key, field);
            HotkeyManager.Current.Register(field);
        }

        private static int NormalizeVolumeStep(int value)
        {
            switch (value)
            {
                case 1:
                case 2:
                case 5:
                case 10:
                    return value;
                default:
                    return 2;
            }
        }

        public HotkeyData FlyoutHotkey { get => _flyoutHotkey; set => SetHotkey("Hotkey", ref _flyoutHotkey, value); }
        public HotkeyData MixerHotkey { get => _mixerHotkey; set => SetHotkey("MixerHotkey", ref _mixerHotkey, value); }
        public HotkeyData SettingsHotkey { get => _settingsHotkey; set => SetHotkey("SettingsHotkey", ref _settingsHotkey, value); }
        public HotkeyData AbsoluteVolumeUpHotkey { get => _absoluteVolumeUpHotkey; set => SetHotkey("AbsoluteVolumeUpHotkey", ref _absoluteVolumeUpHotkey, value); }
        public HotkeyData AbsoluteVolumeDownHotkey { get => _absoluteVolumeDownHotkey; set => SetHotkey("AbsoluteVolumeDownHotkey", ref _absoluteVolumeDownHotkey, value); }
        public HotkeyData ToggleMuteHotkey { get => _toggleMuteHotkey; set => SetHotkey("ToggleMuteHotkey", ref _toggleMuteHotkey, value); }
        public HotkeyData CycleOutputDeviceHotkey { get => _cycleOutputDeviceHotkey; set => SetHotkey("CycleOutputDeviceHotkey", ref _cycleOutputDeviceHotkey, value); }

        public bool IsExpanded
        {
            get => _isExpanded;
            set { if (_isExpanded == value) return; _isExpanded = value; _settings.Set("IsExpanded", value); }
        }

        public bool UseScrollWheelInTray
        {
            get => _useScrollWheelInTray;
            set { if (_useScrollWheelInTray == value) return; _useScrollWheelInTray = value; _settings.Set("UseScrollWheelInTray", value); }
        }

        public bool UseGlobalMouseWheelHook
        {
            get => _useGlobalMouseWheelHook;
            set { if (_useGlobalMouseWheelHook == value) return; _useGlobalMouseWheelHook = value; _settings.Set("UseGlobalMouseWheelHook", value); }
        }

        public int VolumeStep
        {
            get => _volumeStep;
            set
            {
                var normalized = NormalizeVolumeStep(value);
                if (_volumeStep == normalized) return;
                _volumeStep = normalized;
                _settings.Set("VolumeStep", normalized);
            }
        }

        public WINDOWPLACEMENT? FullMixerWindowPlacement
        {
            get => _fullMixerWindowPlacement;
            set { _fullMixerWindowPlacement = value; _settings.Set("FullMixerWindowPlacement", value); }
        }

        public WINDOWPLACEMENT? SettingsWindowPlacement
        {
            get => _settingsWindowPlacement;
            set { _settingsWindowPlacement = value; _settings.Set("SettingsWindowPlacement", value); }
        }
    }
}
'@

Write-Text 'EarTrumpet/UI/ViewModels/EarTrumpetShortcutsPageViewModel.cs' @'
using EarTrumpet.Interop.Helpers;
using System.Globalization;

namespace EarTrumpet.UI.ViewModels
{
    internal class EarTrumpetShortcutsPageViewModel : SettingsPageViewModel
    {
        private static readonly string s_hotkeyNoneText = new HotkeyData().ToString();
        public HotkeyViewModel OpenFlyoutHotkey { get; }
        public string DefaultHotKey => s_hotkeyNoneText;
        public HotkeyViewModel OpenMixerHotkey { get; }
        public string DefaultMixerHotKey => s_hotkeyNoneText;
        public HotkeyViewModel OpenSettingsHotkey { get; }
        public string DefaultSettingsHotKey => s_hotkeyNoneText;
        public HotkeyViewModel AbsoluteVolumeUpHotkey { get; }
        public string DefaultAbsoluteVolumeUpHotkey => s_hotkeyNoneText;
        public HotkeyViewModel AbsoluteVolumeDownHotkey { get; }
        public string DefaultAbsoluteVolumeDownHotkey => s_hotkeyNoneText;
        public HotkeyViewModel ToggleMuteHotkey { get; }
        public string DefaultToggleMuteHotkey => s_hotkeyNoneText;
        public HotkeyViewModel CycleOutputDeviceHotkey { get; }
        public string DefaultCycleOutputDeviceHotkey => s_hotkeyNoneText;
        public string ToggleMuteText => Properties.Resources.ResourceManager.GetString("SettingsToggleMuteHotkeyText", CultureInfo.CurrentUICulture) ?? "Toggle default output mute";
        public string CycleOutputDeviceText => Properties.Resources.ResourceManager.GetString("SettingsCycleOutputDeviceHotkeyText", CultureInfo.CurrentUICulture) ?? "Switch to next playback device";

        public EarTrumpetShortcutsPageViewModel(AppSettings settings) : base(null)
        {
            Title = Properties.Resources.ShortcutsPageText;
            Glyph = "\xE765";
            OpenFlyoutHotkey = new HotkeyViewModel(settings.FlyoutHotkey, value => settings.FlyoutHotkey = value);
            OpenMixerHotkey = new HotkeyViewModel(settings.MixerHotkey, value => settings.MixerHotkey = value);
            OpenSettingsHotkey = new HotkeyViewModel(settings.SettingsHotkey, value => settings.SettingsHotkey = value);
            AbsoluteVolumeUpHotkey = new HotkeyViewModel(settings.AbsoluteVolumeUpHotkey, value => settings.AbsoluteVolumeUpHotkey = value);
            AbsoluteVolumeDownHotkey = new HotkeyViewModel(settings.AbsoluteVolumeDownHotkey, value => settings.AbsoluteVolumeDownHotkey = value);
            ToggleMuteHotkey = new HotkeyViewModel(settings.ToggleMuteHotkey, value => settings.ToggleMuteHotkey = value);
            CycleOutputDeviceHotkey = new HotkeyViewModel(settings.CycleOutputDeviceHotkey, value => settings.CycleOutputDeviceHotkey = value);
        }
    }
}
'@

Write-Text 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' @'
using System.Globalization;

namespace EarTrumpet.UI.ViewModels
{
    public class EarTrumpetMouseSettingsPageViewModel : SettingsPageViewModel
    {
        public bool UseScrollWheelInTray { get => _settings.UseScrollWheelInTray; set => _settings.UseScrollWheelInTray = value; }
        public bool UseGlobalMouseWheelHook { get => _settings.UseGlobalMouseWheelHook; set => _settings.UseGlobalMouseWheelHook = value; }
        public int[] VolumeStepOptions { get; } = new[] { 1, 2, 5, 10 };
        public int VolumeStep
        {
            get => _settings.VolumeStep;
            set { _settings.VolumeStep = value; RaisePropertyChanged(nameof(VolumeStep)); }
        }
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

# Process exit uses Process.EnableRaisingEvents, which delegates to the CLR wait infrastructure.
# One Process object is shared per PID; removing the last callback unregisters/disposes it immediately.
Write-Text 'EarTrumpet/DataModel/ProcessWatcherService.cs' @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;

namespace EarTrumpet.DataModel
{
    public class ProcessWatcherService
    {
        private sealed class CallbackRegistration
        {
            public readonly long Id;
            public readonly Action<int> Callback;
            public CallbackRegistration(long id, Action<int> callback) { Id = id; Callback = callback; }
        }

        private sealed class ProcessWatcherData
        {
            public int ProcessId;
            public readonly List<CallbackRegistration> QuitActions = new List<CallbackRegistration>();
            public Process Process;
            public EventHandler ExitedHandler;
        }

        private sealed class Registration : IDisposable
        {
            private readonly int _processId;
            private readonly long _registrationId;
            private int _disposed;
            public Registration(int processId, long registrationId) { _processId = processId; _registrationId = registrationId; }
            public void Dispose() { if (Interlocked.Exchange(ref _disposed, 1) == 0) UnwatchProcess(_processId, _registrationId); }
        }

        private sealed class EmptyRegistration : IDisposable
        {
            public static readonly EmptyRegistration Instance = new EmptyRegistration();
            private EmptyRegistration() { }
            public void Dispose() { }
        }

        private static readonly object s_lock = new object();
        private static readonly Dictionary<int, ProcessWatcherData> s_watchers = new Dictionary<int, ProcessWatcherData>();
        private static long s_nextRegistrationId;

        public static IDisposable WatchProcess(int processId, Action<int> processQuit)
        {
            if (processQuit == null) throw new ArgumentNullException(nameof(processQuit));
            var registrationId = Interlocked.Increment(ref s_nextRegistrationId);
            var callback = new CallbackRegistration(registrationId, processQuit);

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.QuitActions.Add(callback);
                    return new Registration(processId, registrationId);
                }
            }

            Process process;
            try { process = Process.GetProcessById(processId); }
            catch (ArgumentException) { return EmptyRegistration.Instance; }
            catch (InvalidOperationException) { return EmptyRegistration.Instance; }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService open failed for {processId}: {ex.Message}");
                return EmptyRegistration.Instance;
            }

            var data = new ProcessWatcherData { ProcessId = processId, Process = process };
            data.QuitActions.Add(callback);
            data.ExitedHandler = (_, __) => CompleteWatcher(data, true);
            process.Exited += data.ExitedHandler;

            var raced = false;
            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.QuitActions.Add(callback);
                    raced = true;
                }
                else
                {
                    s_watchers.Add(processId, data);
                }
            }

            if (raced)
            {
                DisposeProcess(data);
                return new Registration(processId, registrationId);
            }

            try { process.EnableRaisingEvents = true; }
            catch (InvalidOperationException ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                CompleteWatcher(data, false);
                return EmptyRegistration.Instance;
            }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                CompleteWatcher(data, false);
                return EmptyRegistration.Instance;
            }

            return new Registration(processId, registrationId);
        }

        private static void UnwatchProcess(int processId, long registrationId)
        {
            ProcessWatcherData toDispose = null;
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(processId, out var data)) return;
                for (var i = data.QuitActions.Count - 1; i >= 0; i--)
                {
                    if (data.QuitActions[i].Id == registrationId) { data.QuitActions.RemoveAt(i); break; }
                }
                if (data.QuitActions.Count == 0)
                {
                    s_watchers.Remove(processId);
                    toDispose = data;
                }
            }
            if (toDispose != null) DisposeProcess(toDispose);
        }

        private static void CompleteWatcher(ProcessWatcherData data, bool invokeCallbacks)
        {
            CallbackRegistration[] callbacks = null;
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data)) return;
                s_watchers.Remove(data.ProcessId);
                if (invokeCallbacks) callbacks = data.QuitActions.ToArray();
                data.QuitActions.Clear();
            }
            DisposeProcess(data);
            if (callbacks == null) return;
            for (var i = 0; i < callbacks.Length; i++)
            {
                try { callbacks[i].Callback(data.ProcessId); }
                catch (Exception ex) { Trace.WriteLine($"ProcessWatcherService callback failed: {ex}"); }
            }
        }

        private static void DisposeProcess(ProcessWatcherData data)
        {
            var process = data.Process;
            data.Process = null;
            var handler = data.ExitedHandler;
            data.ExitedHandler = null;
            if (process == null) return;
            try { if (handler != null) process.Exited -= handler; }
            catch (InvalidOperationException) { }
            finally { process.Dispose(); }
        }
    }
}
'@

$devicePath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$device = Read-Text $devicePath
if (-not $device.Contains('public void ToggleDefaultMute()')) {
    $anchor = '        public void MoveAppToDevice(IAppItemViewModel app, DeviceViewModel dev)'
    if (-not $device.Contains($anchor)) { throw 'DeviceCollectionViewModel insertion anchor was not found.' }
    $methods = @'
        public void ToggleDefaultMute()
        {
            var device = Default;
            if (device != null) device.IsMuted = !device.IsMuted;
        }

        public void CycleDefaultDevice()
        {
            var count = AllDevices.Count;
            if (count == 0) return;
            var currentId = Default?.Id;
            var currentIndex = -1;
            if (currentId != null)
            {
                for (var i = 0; i < count; i++)
                {
                    if (string.Equals(AllDevices[i].Id, currentId, StringComparison.Ordinal)) { currentIndex = i; break; }
                }
            }
            var nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % count;
            if (nextIndex == currentIndex) return;
            AllDevices[nextIndex].MakeDefaultDevice();
        }

'@
    Write-Text $devicePath ($device.Replace($anchor, $methods + $anchor))
}

$appPath = 'EarTrumpet/App.xaml.cs'
$app = Read-Text $appPath
if (-not $app.Contains('Settings.ToggleMuteHotkeyTyped += CollectionViewModel.ToggleDefaultMute;')) {
    $anchor = '            Settings.AbsoluteVolumeDownHotkeyTyped += AbsoluteVolumeDecrement;'
    if (-not $app.Contains($anchor)) { throw 'App hotkey insertion anchor was not found.' }
    $extra = "`r`n            Settings.ToggleMuteHotkeyTyped += CollectionViewModel.ToggleDefaultMute;`r`n            Settings.CycleOutputDeviceHotkeyTyped += CollectionViewModel.CycleDefaultDevice;"
    $app = $app.Replace($anchor, $anchor + $extra)
}
$app = $app.Replace('_trayIcon.TertiaryInvoke += (_, __) => CollectionViewModel.Default?.ToggleMute.Execute(null);', '_trayIcon.TertiaryInvoke += (_, __) => CollectionViewModel.ToggleDefaultMute();')
$app = $app.Replace('CollectionViewModel.Default?.IncrementVolume(Math.Sign(wheelDelta) * 2);', 'CollectionViewModel.Default?.IncrementVolume(Math.Sign(wheelDelta) * Settings.VolumeStep);')
$app = $app.Replace('device.IncrementVolume(2);', 'device.IncrementVolume(Settings.VolumeStep);')
$app = $app.Replace('device.Volume -= 2;', 'device.Volume -= Settings.VolumeStep;')
Write-Text $appPath $app

$settingsPath = 'EarTrumpet/UI/Views/SettingsWindow.xaml'
$settings = Read-Text $settingsPath
if (-not $settings.Contains('Content="{Binding ToggleMuteHotkey}"')) {
    $anchor = '                <TextBlock Style="{StaticResource BodyText}" Text="{x:Static resx:Resources.SettingsAbsoluteVolumeUpText}" />'
    if (-not $settings.Contains($anchor)) { throw 'SettingsWindow shortcut insertion anchor was not found.' }
    $extra = @'
                <TextBlock Style="{StaticResource BodyText}" Text="{Binding ToggleMuteText}" />
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                    <TextBlock VerticalAlignment="Center" Style="{StaticResource BodySubText}" Text="{x:Static resx:Resources.DefaultHotkeyDescriptionText}" />
                    <TextBlock Grid.Column="1" VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding DefaultToggleMuteHotkey}" />
                    <TextBlock Grid.Row="1" VerticalAlignment="Center" Style="{StaticResource BodySubText}" Text="{x:Static resx:Resources.HotkeyDescriptionText}" />
                    <ContentControl Grid.Row="1" Grid.Column="1" Content="{Binding ToggleMuteHotkey}" IsTabStop="False" />
                </Grid>
                <TextBlock Style="{StaticResource BodyText}" Text="{Binding CycleOutputDeviceText}" />
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                    <TextBlock VerticalAlignment="Center" Style="{StaticResource BodySubText}" Text="{x:Static resx:Resources.DefaultHotkeyDescriptionText}" />
                    <TextBlock Grid.Column="1" VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding DefaultCycleOutputDeviceHotkey}" />
                    <TextBlock Grid.Row="1" VerticalAlignment="Center" Style="{StaticResource BodySubText}" Text="{x:Static resx:Resources.HotkeyDescriptionText}" />
                    <ContentControl Grid.Row="1" Grid.Column="1" Content="{Binding CycleOutputDeviceHotkey}" IsTabStop="False" />
                </Grid>
'@
    $settings = $settings.Replace($anchor, $extra + $anchor)
}

function Repair-AbsoluteDefaultBinding([string]$Text, [string]$HeaderToken, [string]$ContentToken, [string]$PropertyName) {
    $contentPos = $Text.IndexOf($ContentToken, [StringComparison]::Ordinal)
    if ($contentPos -lt 0) { throw ('SettingsWindow content token not found: ' + $ContentToken) }
    $start = $Text.LastIndexOf($HeaderToken, $contentPos, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw ('SettingsWindow header token not found: ' + $HeaderToken) }
    $segment = $Text.Substring($start, $contentPos - $start)
    $newBinding = 'Text="{Binding ' + $PropertyName + '}"'
    $segment = $segment.Replace('Text="{Binding DefaultSettingsHotKey}"', $newBinding)
    return $Text.Substring(0, $start) + $segment + $Text.Substring($contentPos)
}
$settings = Repair-AbsoluteDefaultBinding $settings 'SettingsAbsoluteVolumeUpText' 'Content="{Binding AbsoluteVolumeUpHotkey}"' 'DefaultAbsoluteVolumeUpHotkey'
$settings = Repair-AbsoluteDefaultBinding $settings 'SettingsAbsoluteVolumeDownText' 'Content="{Binding AbsoluteVolumeDownHotkey}"' 'DefaultAbsoluteVolumeDownHotkey'

if (-not $settings.Contains('ItemsSource="{Binding VolumeStepOptions}"')) {
    $pattern = '(?s)(<CheckBox\s+HorizontalAlignment="Left"\s+Content="\{x:Static resx:Resources\.SettingsUseGlobalMouseWheelHook\}"\s+IsChecked="\{Binding UseGlobalMouseWheelHook, Mode=TwoWay\}"\s*/>)'
    $rx = New-Object Text.RegularExpressions.Regex($pattern)
    if ($rx.Matches($settings).Count -ne 1) { throw 'SettingsWindow global mouse hook anchor was not uniquely found.' }
    $volumeStep = @'
                <StackPanel Margin="0,12,0,0" Orientation="Horizontal">
                    <TextBlock VerticalAlignment="Center" Style="{StaticResource BodyText}" Text="{Binding VolumeStepText}" />
                    <ComboBox Width="80" Margin="12,0,0,0" ItemsSource="{Binding VolumeStepOptions}" SelectedItem="{Binding VolumeStep, Mode=TwoWay}" />
                </StackPanel>
'@
    $settings = $rx.Replace($settings, '$1' + "`r`n" + $volumeStep, 1)
}
Write-Text $settingsPath $settings

Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.resx' 'SettingsToggleMuteHotkeyText' 'Toggle default output mute'
Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.resx' 'SettingsCycleOutputDeviceHotkeyText' 'Switch to next playback device'
Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.resx' 'SettingsVolumeStepText' 'Volume step (%)'
Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsToggleMuteHotkeyText' '既定の出力をミュート切り替え'
Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsCycleOutputDeviceHotkeyText' '次の再生デバイスへ切り替え'
Ensure-ResxStringFinal 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsVolumeStepText' '音量の変更幅 (%)'

# Architecture invariants: idle process tracking is event-driven and audio setters remain direct.
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'process.EnableRaisingEvents = true;'
Assert-NotContains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'Thread.Sleep('
Assert-NotContains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'PollIntervalMilliseconds'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'ToggleMuteHotkeyTyped'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'CycleOutputDeviceHotkeyTyped'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'public int VolumeStep'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs' 'public void CycleDefaultDevice()'
Assert-Contains 'EarTrumpet/App.xaml.cs' 'Math.Sign(wheelDelta) * Settings.VolumeStep'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Content="{Binding ToggleMuteHotkey}"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Content="{Binding CycleOutputDeviceHotkey}"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'ItemsSource="{Binding VolumeStepOptions}"'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' '_deviceVolume.SetMasterVolumeLevelScalar(rawVolume, ref dummy);'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' '_simpleVolume.SetMasterVolume(rawVolume, ref dummy);'
