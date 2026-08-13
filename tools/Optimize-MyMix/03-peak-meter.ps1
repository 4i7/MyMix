# -----------------------------------------------------------------------------
# 3. Peak meter: retain a real 30 FPS meter, but collapse the Core Audio read to
#    one aggregate GetPeakValue() call per stream, remove per-frame arrays, cache
#    topology snapshots, coalesce UI work, and apply a cheap release smoothing.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' @'
using EarTrumpet.Extensions;
using EarTrumpet.Interop;
using EarTrumpet.Interop.MMDeviceAPI;
using System;

namespace EarTrumpet.DataModel.WindowsAudio.Internal
{
    class Helpers
    {
        public static float ReadPeakValue(IAudioMeterInformation meter)
        {
            if (meter == null)
            {
                return 0f;
            }

            try
            {
                return meter.GetPeakValue();
            }
            catch (Exception ex) when (ex.Is(HRESULT.AUDCLNT_E_DEVICE_INVALIDATED))
            {
                return 0f;
            }
        }
    }
}
'@

Write-Text 'EarTrumpet/DataModel/Audio/IAudioDeviceSession.cs' @'
using EarTrumpet.DataModel.WindowsAudio;
using System.Collections.ObjectModel;

namespace EarTrumpet.DataModel.Audio
{
    public interface IAudioDeviceSession : IStreamWithVolumeControl
    {
        IAudioDevice Parent { get; }
        string DisplayName { get; }
        string ExeName { get; }
        string IconPath { get; }
        bool IsDesktopApp { get; }
        bool IsSystemSoundsSession { get; }
        int ProcessId { get; }
        string AppId { get; }
        SessionState State { get; }
        ObservableCollection<IAudioDeviceSession> Children { get; }
    }
}
'@

Write-Text 'EarTrumpet/DataModel/WindowsAudio/IAudioDeviceWindowsAudio.cs' @'
using EarTrumpet.DataModel.Audio;

namespace EarTrumpet.DataModel.WindowsAudio
{
    public interface IAudioDeviceWindowsAudio : IAudioDevice
    {
        string EnumeratorName { get; }
        string InterfaceName { get; }
        string DeviceDescription { get; }
    }
}
'@

$devicePath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs'
$device = Read-Text $devicePath
$device = [regex]::Replace($device, '(?m)^\s*private readonly FilteredCollectionChain<IAudioDeviceSession> _sessionFilter;\r?\n', '')
$device = [regex]::Replace($device, '(?m)^\s*private readonly AudioDeviceChannelCollection _channels;\r?\n', '')
$device = [regex]::Replace($device, '(?m)^\s*_channels = new AudioDeviceChannelCollection\(_deviceVolume, _dispatcher\);\r?\n', '')
$device = [regex]::Replace($device, '(?m)^\s*_sessionFilter = new FilteredCollectionChain<IAudioDeviceSession>\(_sessions\.Sessions, _dispatcher\);\r?\n', '')
$device = $device.Replace('                Groups = _sessionFilter.Items;', '                Groups = _sessions.Sessions;')
$device = [regex]::Replace($device, '(?m)^\s*_channels\.OnNotify\(pNotify, data\);\r?\n', '')
$device = [regex]::Replace($device, '(?m)^\s*public IEnumerable<IAudioDeviceChannel> Channels => _channels\.Channels;\r?\n', '')
$device = [regex]::Replace($device, '(?ms)        public void UpdatePeakValue\(\)\s*\{.*?\n        \}(?=\s*public void UnhideSessionsForProcessId)', @'
        public void UpdatePeakValue()
        {
            var peak = Helpers.ReadPeakValue(_meter);
            PeakValue1 = peak;
            PeakValue2 = peak;
            _sessions.UpdatePeakValues();
        }
'@)
$device = [regex]::Replace($device, '(?ms)\s*public void AddFilter\(Func<ObservableCollection<IAudioDeviceSession>, ObservableCollection<IAudioDeviceSession>> filter\)\s*\{.*?\n        \}', '')
Write-Text $devicePath $device

$sessionPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs'
$session = Read-Text $sessionPath
$session = [regex]::Replace($session, '(?m)^\s*public IEnumerable<IAudioDeviceSessionChannel> Channels => _channels\.Channels;\r?\n', '')
$session = [regex]::Replace($session, '(?m)^\s*private readonly AudioDeviceSessionChannelCollection _channels;\r?\n', '')
$session = [regex]::Replace($session, '(?m)^\s*_channels = new AudioDeviceSessionChannelCollection\(\(IChannelAudioVolume\)session, _dispatcher\);\r?\n', '')
$session = [regex]::Replace($session, '(?ms)        public void UpdatePeakValueBackground\(\)\s*\{.*?\n        \}(?=\s*private void ChooseDisplayName)', @'
        public void UpdatePeakValueBackground()
        {
            var peak = Helpers.ReadPeakValue(_meter);
            PeakValue1 = peak;
            PeakValue2 = peak;
        }
'@)
$session = [regex]::Replace($session, '(?ms)        void IAudioSessionEvents\.OnChannelVolumeChanged\(uint ChannelCount, IntPtr afNewChannelVolume, uint ChangedChannel, ref Guid EventContext\)\s*\{.*?\n        \}', @'
        void IAudioSessionEvents.OnChannelVolumeChanged(uint ChannelCount, IntPtr afNewChannelVolume, uint ChangedChannel, ref Guid EventContext)
        {
            // Per-channel control is intentionally not modeled by MyMix.
        }
'@)
Write-Text $sessionPath $session

$collectionPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionCollection.cs'
$sessionCollection = Read-Text $collectionPath
if ($sessionCollection -notmatch '_peakSnapshot') {
    $sessionCollection = $sessionCollection.Replace('        private readonly ObservableCollection<IAudioDeviceSession> _sessions = new ObservableCollection<IAudioDeviceSession>();', "        private readonly ObservableCollection<IAudioDeviceSession> _sessions = new ObservableCollection<IAudioDeviceSession>();`r`n        private volatile IAudioDeviceSession[] _peakSnapshot = new IAudioDeviceSession[0];")
}
if ($sessionCollection -notmatch 'public void UpdatePeakValues\(\)') {
    $marker = '        internal void UnHideSessionsForProcessId(int processId)'
    $method = @'
        public void UpdatePeakValues()
        {
            var snapshot = _peakSnapshot;
            for (var i = 0; i < snapshot.Length; i++)
            {
                ((IAudioDeviceSessionInternal)snapshot[i]).UpdatePeakValueBackground();
            }
        }

'@
    $sessionCollection = $sessionCollection.Replace($marker, $method + $marker)
}
$sessionCollection = $sessionCollection.Replace('                _sessions.Add(new AudioDeviceSessionGroup(parent, new AudioDeviceSessionGroup(parent, session)));', "                _sessions.Add(new AudioDeviceSessionGroup(parent, new AudioDeviceSessionGroup(parent, session)));`r`n                _peakSnapshot = _sessions.ToArray();")
$sessionCollection = $sessionCollection.Replace('                    _sessions.Remove(appGroup);', "                    _sessions.Remove(appGroup);`r`n                    _peakSnapshot = _sessions.ToArray();")
Write-Text $collectionPath $sessionCollection

$groupPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionGroup.cs'
$group = Read-Text $groupPath
$group = [regex]::Replace($group, '(?ms)\s*public IEnumerable<IAudioDeviceSessionChannel> Channels.*?(?=        public IEnumerable<IAudioDeviceSession> Sessions)', "`r`n")
$group = [regex]::Replace($group, '(?m)^\s*public float PeakValue1 => .*?;\r?\n\s*public float PeakValue2 => .*?;\r?\n', "        public float PeakValue1 => _peakValue1;`r`n        public float PeakValue2 => _peakValue2;`r`n")
if ($group -notmatch '_peakSnapshot') {
    $group = $group.Replace('        private readonly ObservableCollection<IAudioDeviceSession> _sessions = new ObservableCollection<IAudioDeviceSession>();', "        private readonly ObservableCollection<IAudioDeviceSession> _sessions = new ObservableCollection<IAudioDeviceSession>();`r`n        private volatile IAudioDeviceSession[] _peakSnapshot = new IAudioDeviceSession[0];`r`n        private float _peakValue1;`r`n        private float _peakValue2;")
}
$group = [regex]::Replace($group, '(?ms)        public void UpdatePeakValueBackground\(\)\s*\{.*?\n        \}(?=\s*private readonly ObservableCollection)', @'
        public void UpdatePeakValueBackground()
        {
            var snapshot = _peakSnapshot;
            var peak1 = 0f;
            var peak2 = 0f;

            for (var i = 0; i < snapshot.Length; i++)
            {
                var session = snapshot[i];
                ((IAudioDeviceSessionInternal)session).UpdatePeakValueBackground();
                if (session.PeakValue1 > peak1) peak1 = session.PeakValue1;
                if (session.PeakValue2 > peak2) peak2 = session.PeakValue2;
            }

            _peakValue1 = peak1;
            _peakValue2 = peak2;
        }
'@)
$group = $group.Replace('            foreach (var session in _sessions.ToArray())', '            foreach (var session in _peakSnapshot)')
$group = $group.Replace('            _sessions.Add(session);', "            _sessions.Add(session);`r`n            _peakSnapshot = _sessions.ToArray();")
$group = $group.Replace('            _sessions.Remove(session);', "            _sessions.Remove(session);`r`n            _peakSnapshot = _sessions.ToArray();")
Write-Text $groupPath $group

# Avoid allocating PropertyChangedEventArgs at 30 FPS for every visible stream and use
# an inexpensive release curve so a 30 FPS sample cadence still appears smooth.
$bindablePath = 'EarTrumpet/BindableBase.cs'
Write-Text $bindablePath @'
using System.ComponentModel;

namespace EarTrumpet
{
    public class BindableBase : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void RaisePropertyChanged(string name)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }

        protected void RaisePropertyChanged(PropertyChangedEventArgs args)
        {
            PropertyChanged?.Invoke(this, args);
        }
    }
}
'@

Write-Text 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' @'
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
'@

$deviceCollectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$deviceCollection = Read-Text $deviceCollectionPath
if ($deviceCollection -notmatch '^using System\.Threading;' -and $deviceCollection -notmatch '\nusing System\.Threading;') {
    $deviceCollection = $deviceCollection.Replace('using System.Timers;', "using System.Timers;`r`nusing System.Threading;")
}
if ($deviceCollection -notmatch '_peakUpdateRunning') {
    $deviceCollection = $deviceCollection.Replace('        private bool _isFullWindowVisible;', "        private bool _isFullWindowVisible;`r`n        private int _peakUpdateRunning;`r`n        private int _peakUiUpdatePending;")
}
$deviceCollection = $deviceCollection.Replace('            _peakMeterTimer = new Timer(1000 / 30); // 30 fps', '            _peakMeterTimer = new Timer(1000.0 / 30.0); // fixed 30 FPS target')
$deviceCollection = [regex]::Replace($deviceCollection, '(?ms)        private void PeakMeterTimer_Elapsed\(object sender, ElapsedEventArgs e\)\s*\{.*?\n        \}(?=\s*public void MoveAppToDevice)', @'
        private void PeakMeterTimer_Elapsed(object sender, ElapsedEventArgs e)
        {
            // Never overlap Core Audio sampling if one frame takes longer than 33 ms.
            if (Interlocked.Exchange(ref _peakUpdateRunning, 1) != 0)
            {
                return;
            }

            try
            {
                _deviceManager.UpdatePeakValues();

                // At most one render-priority UI refresh may be queued. Under temporary UI load we
                // drop stale frames rather than building an ever-growing Dispatcher backlog.
                if (Interlocked.Exchange(ref _peakUiUpdatePending, 1) == 0)
                {
                    _currentDispatcher.BeginInvoke(DispatcherPriority.Render, (Action)(() =>
                    {
                        try
                        {
                            foreach (var device in AllDevices)
                            {
                                device.UpdatePeakValueForeground();
                            }
                        }
                        finally
                        {
                            Interlocked.Exchange(ref _peakUiUpdatePending, 0);
                        }
                    }));
                }
            }
            finally
            {
                Interlocked.Exchange(ref _peakUpdateRunning, 0);
            }
        }
'@)
$deviceCollection = $deviceCollection.Replace('e.PropertyName == nameof(Default.Volume) ||', 'e.PropertyName == nameof(Default.IconKind) ||')
$deviceCollection = $deviceCollection.Replace('TrayPropertyChanged.Invoke();', 'TrayPropertyChanged?.Invoke();')
$deviceCollection = [regex]::Replace($deviceCollection, '(?ms)        public string GetTrayToolTip\(\)\s*\{.*?\n        \}(?=\s*\}\s*$)', @'
        public string GetTrayToolTip()
        {
            if (Default == null)
            {
                return Properties.Resources.NoDeviceTrayText;
            }

            var deviceName = $"{Default.DeviceDescription} ({Default.EnumeratorName})";
            if (string.IsNullOrWhiteSpace(Default.EnumeratorName))
            {
                deviceName = Default.DeviceDescription;
            }
            if (string.IsNullOrWhiteSpace(Default.DeviceDescription) && string.IsNullOrWhiteSpace(Default.EnumeratorName))
            {
                deviceName = Default.DisplayName;
            }
            deviceName = deviceName ?? string.Empty;

            // MyMix intentionally avoids numeric volume text; the tray only updates when the
            // mute/icon bucket or device identity changes, not for every slider tick.
            var stateText = Default.IsMuted ? $"{Properties.Resources.MutedText} - " : string.Empty;
            var prefixText = $"MyMix: {stateText}";
            var maxDeviceNameLength = Math.Max(0, 63 - prefixText.Length);
            if (deviceName.Length > maxDeviceNameLength)
            {
                deviceName = deviceName.Substring(0, maxDeviceNameLength);
            }
            return prefixText + deviceName;
        }
'@)
Write-Text $deviceCollectionPath $deviceCollection
