using System.Globalization;

namespace EarTrumpet.UI.ViewModels
{
    public class EarTrumpetMouseSettingsPageViewModel : SettingsPageViewModel
    {
        public bool UseScrollWheelInTray
        {
            get => _settings.UseScrollWheelInTray;
            set => _settings.UseScrollWheelInTray = value;
        }

        public bool UseGlobalMouseWheelHook
        {
            get => _settings.UseGlobalMouseWheelHook;
            set => _settings.UseGlobalMouseWheelHook = value;
        }

        public int[] VolumeStepOptions { get; } = new[] { 1, 2, 5, 10 };

        public int VolumeStep
        {
            get => _settings.VolumeStep;
            set
            {
                _settings.VolumeStep = value;
                RaisePropertyChanged(nameof(VolumeStep));
            }
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
