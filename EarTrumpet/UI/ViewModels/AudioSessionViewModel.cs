using EarTrumpet.DataModel.Audio;
using EarTrumpet.Extensions;
using EarTrumpet.UI.Helpers;
using System;
using System.ComponentModel;
using System.Windows.Input;

namespace EarTrumpet.UI.ViewModels
{
    public class AudioSessionViewModel : BindableBase, IDisposable
    {
        private const float PeakReleaseFactor = 0.72f;
        private const float PeakFloor = 0.002f;
        private static readonly PropertyChangedEventArgs s_peakValue1Changed = new PropertyChangedEventArgs(nameof(PeakValue1));

        private readonly IStreamWithVolumeControl _stream;
        private bool _isAbsMuted;
        private bool _disposed;
        private float _visiblePeak1;

        public AudioSessionViewModel(IStreamWithVolumeControl stream)
        {
            _stream = stream;
            _stream.PropertyChanged += Stream_PropertyChanged;
            ToggleMute = new RelayCommand(() => IsMuted = !IsMuted);
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

        private static float SmoothPeak(float displayed, float raw)
        {
            if (raw >= displayed) return raw;
            var next = (displayed * PeakReleaseFactor) + (raw * (1f - PeakReleaseFactor));
            return next < PeakFloor ? 0f : next;
        }

        public virtual void UpdatePeakValueForeground()
        {
            var next = SmoothPeak(_visiblePeak1, _stream.PeakValue1);
            if (next == _visiblePeak1) return;
            _visiblePeak1 = next;
            RaisePropertyChanged(s_peakValue1Changed);
        }

        public virtual void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _stream.PropertyChanged -= Stream_PropertyChanged;
        }
    }
}