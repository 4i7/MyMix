# GetPeakValue() is already an aggregate (max-channel) scalar. Keep the two visual rails,
# but drive both from one peak property so each stream produces one binding notification/frame.
foreach ($path in @(
    'EarTrumpet/DataModel/Audio/IStreamWithVolumeControl.cs',
    'EarTrumpet/UI/ViewModels/IAppItemViewModel.cs',
    'EarTrumpet/UI/ViewModels/SettingsAppItemViewModel.cs',
    'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs'
)) {
    $text = Read-Text $path
    $text = [regex]::Replace($text, '(?m)^\s*public float PeakValue2.*\r?\n', '')
    $text = [regex]::Replace($text, '(?m)^\s*float PeakValue2.*\r?\n', '')
    Write-Text $path $text
}

$devicePath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs'
$device = Read-Text $devicePath
$device = [regex]::Replace($device, '(?m)^\s*public float PeakValue2 \{ get; private set; \}\r?\n', '')
$device = [regex]::Replace($device, '(?m)^\s*PeakValue2 = peak;\r?\n', '')
Write-Text $devicePath $device

$sessionPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs'
$session = Read-Text $sessionPath
$session = [regex]::Replace($session, '(?m)^\s*public float PeakValue2 \{ get; private set; \}\r?\n', '')
$session = [regex]::Replace($session, '(?m)^\s*PeakValue2 = peak;\r?\n', '')
Write-Text $sessionPath $session

$groupPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionGroup.cs'
$group = Read-Text $groupPath
$group = [regex]::Replace($group, '(?m)^\s*public float PeakValue2 => _peakValue2;\r?\n', '')
$group = [regex]::Replace($group, '(?m)^\s*private float _peakValue2;\r?\n', '')
$group = [regex]::Replace($group, '(?m)^\s*var peak2 = 0f;\r?\n', '')
$group = [regex]::Replace($group, '(?m)^\s*if \(session\.PeakValue2 > peak2\) peak2 = session\.PeakValue2;\r?\n', '')
$group = [regex]::Replace($group, '(?m)^\s*_peakValue2 = peak2;\r?\n', '')
Write-Text $groupPath $group

$vmPath = 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs'
$vm = Read-Text $vmPath
$vm = [regex]::Replace($vm, '(?m)^\s*private static readonly PropertyChangedEventArgs s_peakValue2Changed.*\r?\n', '')
$vm = [regex]::Replace($vm, '(?m)^\s*private float _visiblePeak2;\r?\n', '')
$vm = [regex]::Replace($vm, '(?m)^\s*public virtual float PeakValue2 => _visiblePeak2;\r?\n', '')
$vm = [regex]::Replace($vm, '(?m)^\s*var next2 = SmoothPeak\(_visiblePeak2, _stream\.PeakValue2\);\r?\n', '')
$vm = [regex]::Replace($vm, '(?ms)\s*if \(next2 != _visiblePeak2\)\s*\{\s*_visiblePeak2 = next2;\s*RaisePropertyChanged\(s_peakValue2Changed\);\s*\}', '')
Write-Text $vmPath $vm

foreach ($path in @('EarTrumpet/UI/Views/AppItemView.xaml', 'EarTrumpet/UI/Views/DeviceView.xaml')) {
    $xaml = Read-Text $path
    $xaml = [regex]::Replace($xaml, '(?m)^\s*PeakValue2="\{Binding [^"]+\}"\r?\n', '')
    Write-Text $path $xaml
}

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
            UpdatePeakWidth();
        }

        private static void OnPeakValue1Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            ((VolumeSlider)d).UpdatePeakWidth();
        }

        private void RefreshMeterGeometry()
        {
            if (_thumb == null) return;
            _meterWidth = Math.Max(0d, ActualWidth - _thumb.ActualWidth);
            UpdatePeakWidth();
        }

        private void UpdatePeakWidth()
        {
            var width = _meterWidth * PeakValue1 * (Value * 0.01d);
            if (_peakMeter1 != null) _peakMeter1.Width = width;
            if (_peakMeter2 != null) _peakMeter2.Width = width;
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

Assert-NotContains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakValue2'
Assert-NotContains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'PeakValue2'
Assert-NotContains 'EarTrumpet/UI/Views/AppItemView.xaml' 'PeakValue2'
Assert-NotContains 'EarTrumpet/UI/Views/DeviceView.xaml' 'PeakValue2'
