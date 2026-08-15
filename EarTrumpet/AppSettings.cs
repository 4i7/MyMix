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
            if (value < 1) return 1;
            if (value > 10) return 10;
            return value;
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