using EarTrumpet.DataModel.Audio;
using EarTrumpet.Extensions;
using EarTrumpet.UI.Helpers;
using System;
using System.ComponentModel;
using System.Windows.Input;

namespace EarTrumpet.UI.ViewModels
{
    public class AudioSessionViewModel : BindableBase
    {
        private const float PeakReleaseFactor = 0.72f;
        private const float PeakFloor = 0.002f;
        private static readonly PropertyChangedEventArgs s_peakValue1Changed = new PropertyChangedEventArgs(nameof(PeakValue1));
        private static readonly PropertyChangedEventArgs s_peakValue2Changed = new PropertyChangedEventArgs(nameof(PeakValue2));

        private readonly IStreamWithVolumeControl _stream;
        private bool _isAbsMuted;
        private float _visiblePeak1;
        private float _visiblePeak2;

        public AudioSessionViewModel(IStreamWithVolumeControl stream)
        {
            _stream = stream;
            _stream.PropertyChanged += Stream_PropertyChanged;
            ToggleMute = new RelayCommand(() => IsMuted = !IsMuted);
        }

        ~AudioSessionViewModel()
        {
            _stream.PropertyChanged -= Stream_PropertyChanged;
        }

        private void Stream_PropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            RaisePropertyChanged(e.PropertyName);
        }

        public string Id => _stream.Id;
        public ICommand ToggleMute { get; }
        public bool IsMuted
        {
            get => _stream.IsMuted;
            set => _stream.IsMuted = value;
        }

        public bool IsAbsMuted
        {
            get => _isAbsMuted;
            set => _isAbsMuted = value;
        }

        public int Volume
        {
            get => _stream.Volume.ToVolumeInt();
            set => _stream.Volume = value / 100f;
        }

        public virtual float PeakValue1 => _visiblePeak1;
        public virtual float PeakValue2 => _visiblePeak2;

        private static float SmoothPeak(float displayed, float raw)
        {
            if (raw >= displayed)
            {
                return raw;
            }

            var next = (displayed * PeakReleaseFactor) + (raw * (1f - PeakReleaseFactor));
            return next < PeakFloor ? 0f : next;
        }

        public virtual void UpdatePeakValueForeground()
        {
            var next1 = SmoothPeak(_visiblePeak1, _stream.PeakValue1);
            var next2 = SmoothPeak(_visiblePeak2, _stream.PeakValue2);

            if (next1 != _visiblePeak1)
            {
                _visiblePeak1 = next1;
                RaisePropertyChanged(s_peakValue1Changed);
            }
            if (next2 != _visiblePeak2)
            {
                _visiblePeak2 = next2;
                RaisePropertyChanged(s_peakValue2Changed);
            }
        }
    }
}