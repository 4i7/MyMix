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