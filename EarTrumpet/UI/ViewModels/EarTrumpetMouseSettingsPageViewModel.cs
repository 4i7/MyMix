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