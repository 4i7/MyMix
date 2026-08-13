# -----------------------------------------------------------------------------
# 11. Core Audio callback coalescing: rapid external/device slider notifications
#     should publish the latest state without synchronously blocking callback threads
#     or queueing an unbounded number of Dispatcher operations.
# -----------------------------------------------------------------------------
$devicePath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs'
$device = Read-Text $devicePath
if ($device -notmatch '_volumeUiUpdatePending') {
    $device = $device.Replace('        private bool _isRegistered;', "        private bool _isRegistered;`r`n        private int _volumeUiUpdatePending;")
}
$device = [regex]::Replace($device, '(?ms)\s*_dispatcher\.Invoke\(\(Action\)\(\(\) =>\s*\{\s*RaisePropertyChanged\(nameof\(Volume\)\);\s*RaisePropertyChanged\(nameof\(IsMuted\)\);\s*\}\)\);', "`r`n            QueueVolumeUiUpdate();")
if ($device -notmatch 'private void QueueVolumeUiUpdate\(\)') {
    $marker = '        public float Volume'
    $method = @'
        private void QueueVolumeUiUpdate()
        {
            if (System.Threading.Interlocked.Exchange(ref _volumeUiUpdatePending, 1) != 0) return;
            _dispatcher.BeginInvoke(DispatcherPriority.DataBind, (Action)(() =>
            {
                System.Threading.Interlocked.Exchange(ref _volumeUiUpdatePending, 0);
                RaisePropertyChanged(nameof(Volume));
                RaisePropertyChanged(nameof(IsMuted));
            }));
        }

'@
    $device = $device.Replace($marker, $method + $marker)
}
Write-Text $devicePath $device

$sessionPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs'
$session = Read-Text $sessionPath
if ($session -notmatch '_volumeUiUpdatePending') {
    $session = $session.Replace('        private bool _isRegistered;', "        private bool _isRegistered;`r`n        private int _volumeUiUpdatePending;")
}
$session = [regex]::Replace($session, '(?ms)\s*_dispatcher\.BeginInvoke\(\(Action\)\(\(\) =>\s*\{\s*RaisePropertyChanged\(nameof\(Volume\)\);\s*RaisePropertyChanged\(nameof\(IsMuted\)\);\s*\}\)\);', "`r`n            QueueVolumeUiUpdate();")
if ($session -notmatch 'private void QueueVolumeUiUpdate\(\)') {
    $marker = '        void IAudioSessionEvents.OnGroupingParamChanged'
    $method = @'
        private void QueueVolumeUiUpdate()
        {
            if (System.Threading.Interlocked.Exchange(ref _volumeUiUpdatePending, 1) != 0) return;
            _dispatcher.BeginInvoke(DispatcherPriority.DataBind, (Action)(() =>
            {
                System.Threading.Interlocked.Exchange(ref _volumeUiUpdatePending, 0);
                RaisePropertyChanged(nameof(Volume));
                RaisePropertyChanged(nameof(IsMuted));
            }));
        }

'@
    $session = $session.Replace($marker, $method + $marker)
}
Write-Text $sessionPath $session

Assert-Contains $devicePath 'QueueVolumeUiUpdate();'
Assert-Contains $sessionPath 'QueueVolumeUiUpdate();'
Assert-Contains $devicePath 'DispatcherPriority.DataBind'
Assert-Contains $sessionPath 'DispatcherPriority.DataBind'
