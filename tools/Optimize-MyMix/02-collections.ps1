# -----------------------------------------------------------------------------
# 2. Remove filter/add-on proxy collections. They had no remaining consumers after
#    add-on removal and duplicated every device/session collection notification.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/DataModel/Audio/IAudioDeviceManager.cs' @'
using System;
using System.Collections.ObjectModel;

namespace EarTrumpet.DataModel.Audio
{
    public interface IAudioDeviceManager
    {
        event EventHandler<IAudioDevice> DefaultChanged;
        event EventHandler Loaded;
        IAudioDevice Default { get; set; }
        ObservableCollection<IAudioDevice> Devices { get; }
        string Kind { get; }
        void UpdatePeakValues();
    }
}
'@

Write-Text 'EarTrumpet/DataModel/Audio/IAudioDevice.cs' @'
using System.Collections.ObjectModel;

namespace EarTrumpet.DataModel.Audio
{
    public interface IAudioDevice : IStreamWithVolumeControl
    {
        string DisplayName { get; }
        string IconPath { get; }
        IAudioDeviceManager Parent { get; }
        ObservableCollection<IAudioDeviceSession> Groups { get; }
    }
}
'@

$managerPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceManager.cs'
$manager = Read-Text $managerPath
$manager = $manager.Replace('        public ObservableCollection<IAudioDevice> Devices { get; }', '        public ObservableCollection<IAudioDevice> Devices => _devices;')
$manager = [regex]::Replace($manager, '(?m)^\s*private readonly FilteredCollectionChain<IAudioDevice> _deviceFilter;\r?\n', '')
if ($manager -notmatch '_peakDeviceSnapshot') {
    $manager = $manager.Replace('        private readonly ObservableCollection<IAudioDevice> _devices = new ObservableCollection<IAudioDevice>();', "        private readonly ObservableCollection<IAudioDevice> _devices = new ObservableCollection<IAudioDevice>();`r`n        private volatile IAudioDevice[] _peakDeviceSnapshot = new IAudioDevice[0];")
}
$manager = [regex]::Replace($manager, '(?m)^\s*_deviceFilter = new FilteredCollectionChain<IAudioDevice>\(_devices, _dispatcher\);\r?\n', '')
$manager = [regex]::Replace($manager, '(?m)^\s*Devices = _deviceFilter\.Items;\r?\n', '')
$manager = [regex]::Replace($manager, '(?ms)        public void UpdatePeakValues\(\)\s*\{.*?\n        \}(?=\s*void IMMNotificationClient\.OnDeviceAdded)', @'
        public void UpdatePeakValues()
        {
            var snapshot = _peakDeviceSnapshot;
            for (var i = 0; i < snapshot.Length; i++)
            {
                ((IAudioDeviceInternal)snapshot[i]).UpdatePeakValue();
            }
        }
'@)
$manager = [regex]::Replace($manager, '(?ms)\s*public void AddFilter\(Func<ObservableCollection<IAudioDevice>, ObservableCollection<IAudioDevice>> filter\)\s*\{.*?\n        \}', '')
$manager = $manager.Replace('                _devices.Add(device);', "                _devices.Add(device);`r`n                _peakDeviceSnapshot = _devices.ToArray();")
$manager = $manager.Replace('                _devices.Remove(device);', "                _devices.Remove(device);`r`n                _peakDeviceSnapshot = _devices.ToArray();")
Write-Text $managerPath $manager
