using EarTrumpet.DataModel.Audio;
using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.Extensions;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Timers;
using System.Windows.Threading;

namespace EarTrumpet.UI.ViewModels
{
    public class DeviceCollectionViewModel : BindableBase
    {
        private static readonly string DefaultDeviceChangedProperty = "DefaultDeviceChangedProperty";

        public event EventHandler<DeviceViewModel> DefaultChanged;
        public event Action TrayPropertyChanged;

        public ObservableCollection<DeviceViewModel> AllDevices { get; private set; } = new ObservableCollection<DeviceViewModel>();
        public DeviceViewModel Default { get; private set; }

        private readonly IAudioDeviceManager _deviceManager;
        private readonly Timer _peakMeterTimer;
        private readonly AppSettings _settings;
        private readonly Dispatcher _currentDispatcher = Dispatcher.CurrentDispatcher;
        private bool _isFlyoutVisible;
        private bool _isFullWindowVisible;
        private int _peakUpdateRunning;
        private int _peakUiUpdatePending;

        public DeviceCollectionViewModel(IAudioDeviceManager deviceManager, AppSettings settings)
        {
            _settings = settings;
            _deviceManager = deviceManager;
            _deviceManager.DefaultChanged += OnDefaultChanged;
            _deviceManager.Devices.CollectionChanged += OnCollectionChanged;
            OnCollectionChanged(null, new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));

            _peakMeterTimer = new Timer(1000.0 / 30.0); // fixed 30 FPS target
            _peakMeterTimer.AutoReset = true;
            _peakMeterTimer.Elapsed += PeakMeterTimer_Elapsed;
        }

        private void OnDefaultChanged(object sender, IAudioDevice newDevice)
        {
            if (newDevice == null)
            {
                SetDefault(null);
            }
            else
            {
                var device = AllDevices.FirstOrDefault(d => d.Id == newDevice.Id);
                if (device == null)
                {
                    AddDevice(newDevice);
                    device = AllDevices.FirstOrDefault(d => d.Id == newDevice.Id);
                }
                SetDefault(device);
            }
        }

        private void SetDefault(DeviceViewModel device)
        {
            if (Default != null)
            {
                Default.PropertyChanged -= OnDefaultDevicePropertyChanged;
            }

            Default = device;
            DefaultChanged?.Invoke(this, Default);

            if (Default != null)
            {
                Default.PropertyChanged += OnDefaultDevicePropertyChanged;
            }

            // Let clients know that even though no properties changed, the underlying object changed.
            OnDefaultDevicePropertyChanged(this, new PropertyChangedEventArgs(DefaultDeviceChangedProperty));
        }

        private void OnDefaultDevicePropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == DefaultDeviceChangedProperty ||
                e.PropertyName == nameof(Default.IconKind) ||
                e.PropertyName == nameof(Default.IsMuted) ||
                e.PropertyName == nameof(Default.DisplayName))
            {
                TrayPropertyChanged?.Invoke();
            }
        }

        protected virtual void AddDevice(IAudioDevice device)
        {
            var newDevice = new DeviceViewModel(this, _deviceManager, device);
            AllDevices.AddSorted(newDevice, DeviceViewModel.CompareByDisplayName);
        }

        private void OnCollectionChanged(object sender, NotifyCollectionChangedEventArgs e)
        {
            switch (e.Action)
            {
                case NotifyCollectionChangedAction.Add:
                    var added = ((IAudioDevice)e.NewItems[0]);
                    var allExistingAdded = AllDevices.FirstOrDefault(d => d.Id == added.Id);
                    if (allExistingAdded == null)
                    {
                        AddDevice(added);
                    }
                    break;

                case NotifyCollectionChangedAction.Remove:
                    var removed = ((IAudioDevice)e.OldItems[0]).Id;
                    var allExisting = AllDevices.FirstOrDefault(d => d.Id == removed);
                    if (allExisting != null)
                    {
                        allExisting.Dispose();
                        AllDevices.Remove(allExisting);
                    }
                    break;

                case NotifyCollectionChangedAction.Reset:
                   for (var i = 0; i < AllDevices.Count; i++) AllDevices[i].Dispose();
                    AllDevices.Clear();
                    foreach (var device in _deviceManager.Devices)
                    {
                        AddDevice(device);
                    }
                    break;

                default:
                    throw new NotImplementedException();
            }
        }

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
        private void PeakMeterTimer_Elapsed(object sender, ElapsedEventArgs e)
        {
            // Never overlap Core Audio sampling if one frame takes longer than 33 ms.
            if (System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1) != 0)
            {
                return;
            }

            try
            {
                UpdatePeakValuesForVisibleSurfaces();

                // At most one render-priority UI refresh may be queued. Under temporary UI load we
                // drop stale frames rather than building an ever-growing Dispatcher backlog.
                if (System.Threading.Interlocked.Exchange(ref _peakUiUpdatePending, 1) == 0)
                {
                    _currentDispatcher.BeginInvoke(DispatcherPriority.Render, (Action)(() =>
                    {
                        try
                        {
                            UpdatePeakForegroundForVisibleSurfaces();
                        }
                        finally
                        {
                            System.Threading.Interlocked.Exchange(ref _peakUiUpdatePending, 0);
                        }
                    }));
                }
            }
            finally
            {
                System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 0);
            }
        }

        public void MoveAppToDevice(IAppItemViewModel app, DeviceViewModel dev)
        {
            // Collect all matching apps on all devices.
            var apps = new List<IAppItemViewModel>();
            apps.Add(app);

            foreach (var device in AllDevices)
            {
                foreach (var deviceApp in device.Apps)
                {
                    if (deviceApp.DoesGroupWith(app))
                    {
                        if (!apps.Contains(deviceApp))
                        {
                            apps.Add(deviceApp);
                            break;
                        }
                    }
                }
            }

            foreach (var foundApp in apps)
            {
                MoveAppToDeviceInternal(foundApp, dev);
            }

            // Collect and move any hidden/moved sessions.
            ((IAudioDeviceManagerWindowsAudio)_deviceManager).MoveHiddenAppsToDevice(app.AppId, dev?.Id);
        }

        private void MoveAppToDeviceInternal(IAppItemViewModel app, DeviceViewModel device)
        {
            var searchId = device?.Id;
            if (device == null)
            {
                searchId = _deviceManager.Default.Id;
            }

            TemporaryAppItemViewModel tempApp = null;
            try
            {
                DeviceViewModel oldDevice = AllDevices.First(d => d.Apps.Contains(app));
                DeviceViewModel newDevice = AllDevices.First(d => searchId == d.Id);
                bool isLogicallyMovingDevices = oldDevice != newDevice;

                if (isLogicallyMovingDevices)
                {
                    tempApp = new TemporaryAppItemViewModel(this, _deviceManager, app);
                }

                app.MoveToDevice(device?.Id, hide: isLogicallyMovingDevices);

                if (isLogicallyMovingDevices)
                {
                    oldDevice.AppLeavingFromThisDevice(app);
                    newDevice.AppMovingToThisDevice(tempApp);
                    tempApp = null; // destination now owns it, or already disposed it as a duplicate
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"DeviceCollectionViewModel MoveAppToDeviceInternal Failed: {ex}");
            }
            finally
            {
                tempApp?.Dispose();
            }
        }

        private void StartOrStopPeakTimer()
        {
            _peakMeterTimer.Enabled = _isFlyoutVisible || _isFullWindowVisible;
        }

        public void OnTrayFlyoutShown()
        {
            _isFlyoutVisible = true;
            StartOrStopPeakTimer();
        }

        public void OnTrayFlyoutHidden()
        {
            _isFlyoutVisible = false;
            StartOrStopPeakTimer();
        }

        public void OnFullWindowClosed()
        {
            _isFullWindowVisible = false;
            StartOrStopPeakTimer();
        }

        public void OnFullWindowOpened()
        {
            _isFullWindowVisible = true;
            StartOrStopPeakTimer();
        }

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
    }
}