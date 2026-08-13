# Scope 30 FPS peak sampling to what the user can actually see.
# Collapsed tray flyout samples only the default device; expanded/full-window modes sample all.
$managerInterfacePath = 'EarTrumpet/DataModel/Audio/IAudioDeviceManager.cs'
$managerInterface = Read-Text $managerInterfacePath
$managerInterface = $managerInterface.Replace('        void UpdatePeakValues();', '        void UpdatePeakValues(string deviceId = null);')
Write-Text $managerInterfacePath $managerInterface

$managerPath = 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceManager.cs'
$manager = Read-Text $managerPath
$manager = [regex]::Replace($manager, '(?ms)        public void UpdatePeakValues\(\)\s*\{.*?\n        \}(?=\s*void IMMNotificationClient\.OnDeviceAdded)', @'
        public void UpdatePeakValues(string deviceId = null)
        {
            var snapshot = _peakDeviceSnapshot;
            if (deviceId != null)
            {
                for (var i = 0; i < snapshot.Length; i++)
                {
                    if (snapshot[i].Id == deviceId)
                    {
                        ((IAudioDeviceInternal)snapshot[i]).UpdatePeakValue();
                        return;
                    }
                }
                return;
            }

            for (var i = 0; i < snapshot.Length; i++)
            {
                ((IAudioDeviceInternal)snapshot[i]).UpdatePeakValue();
            }
        }
'@)
Write-Text $managerPath $manager

$collectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$collection = Read-Text $collectionPath
if ($collection -notmatch 'ShouldSampleAllPeakDevices') {
    $marker = '        private void PeakMeterTimer_Elapsed(object sender, ElapsedEventArgs e)'
    $helpers = @'
        private bool ShouldSampleAllPeakDevices => _isFullWindowVisible || (_isFlyoutVisible && _settings.IsExpanded);

        private void UpdatePeakValuesForVisibleSurfaces()
        {
            if (ShouldSampleAllPeakDevices)
            {
                _deviceManager.UpdatePeakValues();
            }
            else if (_isFlyoutVisible && Default != null)
            {
                _deviceManager.UpdatePeakValues(Default.Id);
            }
        }

        private void UpdatePeakForegroundForVisibleSurfaces()
        {
            if (ShouldSampleAllPeakDevices)
            {
                foreach (var device in AllDevices)
                {
                    device.UpdatePeakValueForeground();
                }
            }
            else if (_isFlyoutVisible)
            {
                Default?.UpdatePeakValueForeground();
            }
        }

'@
    $collection = $collection.Replace($marker, $helpers + $marker)
}
$collection = $collection.Replace('                _deviceManager.UpdatePeakValues();', '                UpdatePeakValuesForVisibleSurfaces();')
$collection = [regex]::Replace($collection, '(?ms)\s*foreach \(var device in AllDevices\)\s*\{\s*device\.UpdatePeakValueForeground\(\);\s*\}', "`r`n                            UpdatePeakForegroundForVisibleSurfaces();", 1)
Write-Text $collectionPath $collection

Assert-Contains $collectionPath 'ShouldSampleAllPeakDevices'
Assert-Contains $collectionPath '_deviceManager.UpdatePeakValues(Default.Id)'
Assert-Contains $managerPath 'public void UpdatePeakValues(string deviceId = null)'
