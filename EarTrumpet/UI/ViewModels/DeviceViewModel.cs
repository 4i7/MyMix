using EarTrumpet.DataModel.Audio;
using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.Extensions;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;

namespace EarTrumpet.UI.ViewModels
{
    public class DeviceViewModel : AudioSessionViewModel, IDeviceViewModel
    {
        public class DisplayNameComparer : IComparer<DeviceViewModel>
        {
            public int Compare(DeviceViewModel one, DeviceViewModel two) =>
                string.Compare(one.DisplayName, two.DisplayName, StringComparison.CurrentCultureIgnoreCase);
        }

        public static readonly DisplayNameComparer CompareByDisplayName = new DisplayNameComparer();
        private static readonly bool s_isWindows11 = Environment.OSVersion.IsAtLeast(OSVersions.Windows11);
        private static readonly string s_recordingKind = AudioDeviceKind.Recording.ToString();

        public enum DeviceIconKind { Mute, Bar0, Bar1, Bar2, Bar3, Microphone }

        protected readonly IAudioDevice _device;
        protected readonly IAudioDeviceManager _deviceManager;
        protected readonly WeakReference<DeviceCollectionViewModel> _parent;
        private bool _isDisplayNameVisible;
        private DeviceIconKind _iconKind;
        private bool _disposed;

        public string DisplayName => _device.DisplayName;
        public string AccessibleName => IsMuted
            ? Properties.Resources.AppOrDeviceMutedFormatAccessibleText.Replace("{Name}", DisplayName)
            : Properties.Resources.AppOrDeviceFormatAccessibleText.Replace("{Name}", DisplayName).Replace("{Volume}", Volume.ToString());
        public string DeviceDescription => ((IAudioDeviceWindowsAudio)_device).DeviceDescription;
        public string EnumeratorName => ((IAudioDeviceWindowsAudio)_device).EnumeratorName;
        public string InterfaceName => ((IAudioDeviceWindowsAudio)_device).InterfaceName;
        public ObservableCollection<IAppItemViewModel> Apps { get; }

        public bool IsDisplayNameVisible
        {
            get => _isDisplayNameVisible;
            set
            {
                if (_isDisplayNameVisible == value) return;
                _isDisplayNameVisible = value;
                RaisePropertyChanged(nameof(IsDisplayNameVisible));
            }
        }

        public DeviceIconKind IconKind
        {
            get => _iconKind;
            private set
            {
                if (_iconKind == value) return;
                _iconKind = value;
                RaisePropertyChanged(nameof(IconKind));
            }
        }

        public DeviceViewModel(DeviceCollectionViewModel parent, IAudioDeviceManager deviceManager, IAudioDevice device) : base(device)
        {
            _deviceManager = deviceManager;
            _device = device;
            _parent = new WeakReference<DeviceCollectionViewModel>(parent);
            Apps = new ObservableCollection<IAppItemViewModel>();
            _device.PropertyChanged += OnPropertyChanged;
            _device.Groups.CollectionChanged += OnCollectionChanged;

            foreach (var session in _device.Groups)
            {
                Apps.AddSorted(new AppItemViewModel(this, session), AppItemViewModel.CompareByExeName);
            }
            UpdateMasterVolumeIcon();
        }

        private void OnPropertyChanged(object sender, System.ComponentModel.PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(_device.IsMuted) || e.PropertyName == nameof(_device.Volume))
            {
                UpdateMasterVolumeIcon();
                RaisePropertyChanged(nameof(AccessibleName));
            }
            else if (e.PropertyName == nameof(_device.DisplayName))
            {
                RaisePropertyChanged(nameof(DisplayName));
                RaisePropertyChanged(nameof(AccessibleName));
            }
        }

        public override void UpdatePeakValueForeground()
        {
            base.UpdatePeakValueForeground();
            for (var i = 0; i < Apps.Count; i++) Apps[i].UpdatePeakValueForeground();
        }

        private void UpdateMasterVolumeIcon()
        {
            if (_device.Parent.Kind == s_recordingKind)
            {
                IconKind = DeviceIconKind.Microphone;
                return;
            }
            if (_device.IsMuted) IconKind = DeviceIconKind.Mute;
            else if (s_isWindows11 ? _device.Volume > 0.66f : _device.Volume >= 0.66f) IconKind = DeviceIconKind.Bar3;
            else if (s_isWindows11 ? _device.Volume > 0.33f : _device.Volume >= 0.33f) IconKind = DeviceIconKind.Bar2;
            else if (_device.Volume > 0f) IconKind = DeviceIconKind.Bar1;
            else IconKind = DeviceIconKind.Bar0;
        }

        private void OnCollectionChanged(object sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
        {
            if (e.Action == System.Collections.Specialized.NotifyCollectionChangedAction.Add)
            {
                Debug.Assert(e.NewItems.Count == 1);
                AddSession((IAudioDeviceSession)e.NewItems[0]);
                return;
            }
            if (e.Action == System.Collections.Specialized.NotifyCollectionChangedAction.Remove)
            {
                Debug.Assert(e.OldItems.Count == 1);
                var id = ((IAudioDeviceSession)e.OldItems[0]).Id;
                for (var i = 0; i < Apps.Count; i++)
                {
                    if (Apps[i].Id != id) continue;
                    (Apps[i] as IDisposable)?.Dispose();
                    Apps.RemoveAt(i);
                    return;
                }
                return;
            }
            throw new NotImplementedException();
        }

        private void AddSession(IAudioDeviceSession session)
        {
            var newSession = new AppItemViewModel(this, session);
            for (var i = 0; i < Apps.Count; i++)
            {
                var app = Apps[i];
                if (!app.DoesGroupWith(newSession)) continue;
                newSession.Volume = app.Volume;
                newSession.IsMuted = app.IsMuted;
                (app as IDisposable)?.Dispose();
                Apps.RemoveAt(i);
                break;
            }
            Apps.AddSorted(newSession, AppItemViewModel.CompareByExeName);
        }

        public void AppMovingToThisDevice(TemporaryAppItemViewModel app)
        {
            foreach (var childApp in app.ChildApps)
            {
                ((IAudioDeviceManagerWindowsAudio)_deviceManager).UnhideSessionsForProcessId(_device.Id, childApp.ProcessId);
            }

            for (var i = 0; i < Apps.Count; i++)
            {
                if (!Apps[i].DoesGroupWith(app)) continue;
                app.Dispose();
                return;
            }

            app.Expired += OnAppExpired;
            Apps.AddSorted(app, AppItemViewModel.CompareByExeName);
        }

        private void OnAppExpired(object sender, EventArgs e)
        {
            var app = (TemporaryAppItemViewModel)sender;
            app.Expired -= OnAppExpired;
            if (Apps.Contains(app))
            {
                Apps.Remove(app);
            }
            app.Dispose();
        }

        internal void AppLeavingFromThisDevice(IAppItemViewModel app)
        {
            if (app is TemporaryAppItemViewModel temporaryApp)
            {
                temporaryApp.Expired -= OnAppExpired;
                if (Apps.Contains(temporaryApp))
                {
                    Apps.Remove(temporaryApp);
                }
                temporaryApp.Dispose();
            }
        }

        public void MakeDefaultDevice() => _deviceManager.Default = _device;
        public void IncrementVolume(int delta) => Volume += delta;

        public override void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _device.PropertyChanged -= OnPropertyChanged;
            _device.Groups.CollectionChanged -= OnCollectionChanged;
            for (var i = 0; i < Apps.Count; i++) (Apps[i] as IDisposable)?.Dispose();
            base.Dispose();
        }

        public override string ToString() => AccessibleName;
    }
}
