# -----------------------------------------------------------------------------
# 4. Logarithmic hot path: cache display-space volume and a constant mute threshold.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/Extensions/FloatExtensions.cs' @'
using System;

namespace EarTrumpet.Extensions
{
    public static class FloatExtensions
    {
        private const double CurveFactor = 5.757;
        private static readonly double InverseCurveScale = Math.Exp(-CurveFactor);
        public static readonly float MuteThreshold = (float)(Math.Exp(CurveFactor * 0.01) * InverseCurveScale);

        public static int ToVolumeInt(this float val)
        {
            return Convert.ToInt32(Math.Round(val * 100, MidpointRounding.AwayFromZero));
        }

        public static float Bound(this float val, float min, float max)
        {
            return Math.Max(min, Math.Min(max, val));
        }

        public static float ToLogVolume(this float val)
        {
            return ((float)(Math.Exp(CurveFactor * val) * InverseCurveScale)).Bound(0, 1f);
        }

        public static float ToDisplayVolume(this float val)
        {
            if (val <= 0)
            {
                return 0;
            }
            return ((float)((Math.Log(val) + CurveFactor) / CurveFactor)).Bound(0, 1f);
        }
    }
}
'@

$device = Read-Text $devicePath
if ($device -notmatch 'private float _displayVolume;') {
    $device = $device.Replace('        private float _volume;', "        private float _volume;`r`n        private float _displayVolume;")
}
$device = $device.Replace('                _deviceVolume.GetMasterVolumeLevelScalar(out _volume);', "                _deviceVolume.GetMasterVolumeLevelScalar(out _volume);`r`n                _displayVolume = _volume.ToDisplayVolume();")
$device = $device.Replace('            _volume = data.fMasterVolume;', "            _volume = data.fMasterVolume;`r`n            _displayVolume = _volume.ToDisplayVolume();")
$device = [regex]::Replace($device, '(?ms)        public float Volume\s*\{.*?\n        \}(?=\s*public float PeakValue1)', @'
        public float Volume
        {
            get => _displayVolume;
            set
            {
                var displayVolume = value.Bound(0, 1f);
                var rawVolume = displayVolume.ToLogVolume();

                if (_volume != rawVolume)
                {
                    try
                    {
                        _volume = rawVolume;
                        _displayVolume = displayVolume;
                        Guid dummy = Guid.Empty;
                        _deviceVolume.SetMasterVolumeLevelScalar(rawVolume, ref dummy);
                    }
                    catch (Exception ex) when (ex.Is(HRESULT.AUDCLNT_E_DEVICE_INVALIDATED))
                    {
                    }

                    IsMuted = _volume <= FloatExtensions.MuteThreshold;
                }
            }
        }
'@)
Write-Text $devicePath $device

$session = Read-Text $sessionPath
if ($session -notmatch 'private float _displayVolume;') {
    $session = $session.Replace('        private float _volume;', "        private float _volume;`r`n        private float _displayVolume;")
}
$session = $session.Replace('            _simpleVolume.GetMasterVolume(out _volume);', "            _simpleVolume.GetMasterVolume(out _volume);`r`n            _displayVolume = _volume.ToDisplayVolume();")
$session = $session.Replace('            _volume = NewVolume;', "            _volume = NewVolume;`r`n            _displayVolume = _volume.ToDisplayVolume();")
$session = [regex]::Replace($session, '(?ms)        public float Volume\s*\{.*?\n        \}(?=\s*public bool IsMuted)', @'
        public float Volume
        {
            get => _displayVolume;
            set
            {
                var displayVolume = value.Bound(0, 1f);
                var rawVolume = displayVolume.ToLogVolume();

                if (_volume != rawVolume)
                {
                    try
                    {
                        _volume = rawVolume;
                        _displayVolume = displayVolume;
                        Guid dummy = Guid.Empty;
                        _simpleVolume.SetMasterVolume(rawVolume, ref dummy);
                    }
                    catch (Exception ex) when (ex.Is(HRESULT.AUDCLNT_E_DEVICE_INVALIDATED))
                    {
                    }

                    IsMuted = _volume <= FloatExtensions.MuteThreshold;
                }
            }
        }
'@)
Write-Text $sessionPath $session

$deviceVmPath = 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs'
$deviceVm = Read-Text $deviceVmPath
if ($deviceVm -notmatch 's_isWindows11') {
    $deviceVm = $deviceVm.Replace('        public static readonly DisplayNameComparer CompareByDisplayName = new DisplayNameComparer();', "        public static readonly DisplayNameComparer CompareByDisplayName = new DisplayNameComparer();`r`n        private static readonly bool s_isWindows11 = Environment.OSVersion.IsAtLeast(OSVersions.Windows11);")
}
$deviceVm = $deviceVm.Replace('                var isOnWindows11 = Environment.OSVersion.IsAtLeast(OSVersions.Windows11);', '                var isOnWindows11 = s_isWindows11;')
Write-Text $deviceVmPath $deviceVm

$appVmPath = 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs'
$appVm = Read-Text $appVmPath
$appVm = [regex]::Replace($appVm, '(?m)^\s*public char IconText => .*?;\r?\n', @'
        public char IconText
        {
            get
            {
                var name = DisplayName;
                if (string.IsNullOrWhiteSpace(name)) return '?';
                foreach (var c in name)
                {
                    if (char.IsLetterOrDigit(c)) return char.ToUpperInvariant(c);
                }
                return '?';
            }
        }
'@ + "`r`n")
Write-Text $appVmPath $appVm

# Peak UI control: each peak binding updates only its own bar. Track geometry is cached
# on arrange/value changes, avoiding duplicate width calculations for both bars per notification.
Write-Text 'EarTrumpet/UI/Controls/VolumeSlider.cs' @'
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;

namespace EarTrumpet.UI.Controls
{
    public class VolumeSlider : Slider
    {
        public float PeakValue1
        {
            get => (float)GetValue(PeakValue1Property);
            set => SetValue(PeakValue1Property, value);
        }
        public static readonly DependencyProperty PeakValue1Property = DependencyProperty.Register(
            nameof(PeakValue1), typeof(float), typeof(VolumeSlider), new PropertyMetadata(0f, OnPeakValue1Changed));

        public float PeakValue2
        {
            get => (float)GetValue(PeakValue2Property);
            set => SetValue(PeakValue2Property, value);
        }
        public static readonly DependencyProperty PeakValue2Property = DependencyProperty.Register(
            nameof(PeakValue2), typeof(float), typeof(VolumeSlider), new PropertyMetadata(0f, OnPeakValue2Changed));

        private Border _peakMeter1;
        private Border _peakMeter2;
        private Thumb _thumb;
        private Point _lastMousePosition;
        private double _meterWidth;

        public VolumeSlider()
        {
            PreviewTouchDown += OnTouchDown;
            PreviewMouseDown += OnMouseDown;
            TouchUp += OnTouchUp;
            MouseUp += OnMouseUp;
            TouchMove += OnTouchMove;
            MouseMove += OnMouseMove;
            MouseWheel += OnMouseWheel;
            Loaded += OnLoaded;
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            _thumb = (Thumb)GetTemplateChild("SliderThumb");
            _peakMeter1 = (Border)GetTemplateChild("PeakMeter1");
            _peakMeter2 = (Border)GetTemplateChild("PeakMeter2");
            RefreshMeterGeometry();
        }

        protected override Size ArrangeOverride(Size arrangeBounds)
        {
            var result = base.ArrangeOverride(arrangeBounds);
            RefreshMeterGeometry();
            return result;
        }

        protected override void OnValueChanged(double oldValue, double newValue)
        {
            base.OnValueChanged(oldValue, newValue);
            UpdateBothPeakWidths();
        }

        private static void OnPeakValue1Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            ((VolumeSlider)d).UpdatePeak1Width();
        }

        private static void OnPeakValue2Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            ((VolumeSlider)d).UpdatePeak2Width();
        }

        private void RefreshMeterGeometry()
        {
            if (_thumb == null) return;
            _meterWidth = Math.Max(0d, ActualWidth - _thumb.ActualWidth);
            UpdateBothPeakWidths();
        }

        private double PeakScale => Value * 0.01d;

        private void UpdateBothPeakWidths()
        {
            UpdatePeak1Width();
            UpdatePeak2Width();
        }

        private void UpdatePeak1Width()
        {
            if (_peakMeter1 != null) _peakMeter1.Width = _meterWidth * PeakValue1 * PeakScale;
        }

        private void UpdatePeak2Width()
        {
            if (_peakMeter2 != null) _peakMeter2.Width = _meterWidth * PeakValue2 * PeakScale;
        }

        private void OnTouchDown(object sender, TouchEventArgs e)
        {
            VisualStateManager.GoToState((FrameworkElement)sender, "Pressed", true);
            SetPositionByControlPoint(e.GetTouchPoint(this).Position);
            CaptureTouch(e.TouchDevice);
            e.Handled = true;
        }

        private void OnMouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.LeftButton != MouseButtonState.Pressed) return;
            _lastMousePosition = e.GetPosition(this);
            VisualStateManager.GoToState((FrameworkElement)sender, "Pressed", true);
            if (_thumb != null && !_thumb.IsMouseOver) SetPositionByControlPoint(_lastMousePosition);
            CaptureMouse();
            e.Handled = true;
        }

        private void OnTouchUp(object sender, TouchEventArgs e)
        {
            VisualStateManager.GoToState((FrameworkElement)sender, "Normal", true);
            ReleaseTouchCapture(e.TouchDevice);
            e.Handled = true;
        }

        private void OnMouseUp(object sender, MouseButtonEventArgs e)
        {
            if (!IsMouseCaptured) return;
            if (!new Rect(0, 0, ActualWidth, ActualHeight).Contains(e.GetPosition(this)))
            {
                VisualStateManager.GoToState((FrameworkElement)sender, "Normal", true);
            }
            ReleaseMouseCapture();
            e.Handled = true;
        }

        private void OnTouchMove(object sender, TouchEventArgs e)
        {
            if (!AreAnyTouchesCaptured) return;
            SetPositionByControlPoint(e.GetTouchPoint(this).Position);
            e.Handled = true;
        }

        private void OnMouseMove(object sender, MouseEventArgs e)
        {
            if (!IsMouseCaptured) return;
            var mousePosition = e.GetPosition(this);
            if (mousePosition == _lastMousePosition) return;
            _lastMousePosition = mousePosition;
            SetPositionByControlPoint(mousePosition);
        }

        private void OnMouseWheel(object sender, MouseWheelEventArgs e)
        {
            ChangePositionByAmount(Math.Sign(e.Delta) * 2.0);
            e.Handled = true;
        }

        public void SetPositionByControlPoint(Point point)
        {
            if (ActualWidth <= 0) return;
            Value = Bound((Maximum - Minimum) * (point.X / ActualWidth));
        }

        public void ChangePositionByAmount(double amount) => Value = Bound(Value + amount);
        public double Bound(double val) => Math.Max(Minimum, Math.Min(Maximum, val));
    }
}
'@
