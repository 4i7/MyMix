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