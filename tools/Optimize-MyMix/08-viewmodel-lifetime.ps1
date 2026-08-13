# -----------------------------------------------------------------------------
# 8. View-model lifetime: finalizers cannot break publisher->subscriber event roots.
#    Dispose removed devices/apps explicitly to prevent long-lived event retention and
#    eliminate finalizable VM objects from normal session churn.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' @'
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
'@

Write-Text 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs' @'
using EarTrumpet.DataModel.Audio;
using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.DataModel.WindowsAudio.Internal;
using EarTrumpet.Extensions;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Media;

namespace EarTrumpet.UI.ViewModels
{
    public class AppItemViewModel : AudioSessionViewModel, IAppItemViewModel
    {
        public class ExeNameComparer : IComparer<IAppItemViewModel>
        {
            public int Compare(IAppItemViewModel one, IAppItemViewModel two) =>
                string.Compare(one.ExeName, two.ExeName, StringComparison.Ordinal);
        }

        public static readonly ExeNameComparer CompareByExeName = new ExeNameComparer();
        private static readonly bool s_isMovableOs = Environment.OSVersion.IsAtLeast(OSVersions.RS4);

        private readonly IAudioDeviceSession _session;
        private readonly WeakReference<DeviceViewModel> _parent;
        private bool _disposed;

        public Color Background { get; private set; }
        public string DisplayName => _session.DisplayName;
        public string ExeName => _session.ExeName;
        public string AppId => _session.AppId;
        public string IconPath => _session.IconPath;
        public bool IsDesktopApp => _session.IsDesktopApp;
        public bool IsExpanded { get; private set; }
        public int ProcessId => _session.ProcessId;
        public ObservableCollection<IAppItemViewModel> ChildApps { get; private set; }
        public bool IsMovable => !_session.IsSystemSoundsSession && s_isMovableOs;
        public string PersistedOutputDevice => _session.Parent.Parent is IAudioDeviceManagerWindowsAudio manager ? manager.GetDefaultEndPoint(ProcessId) : string.Empty;

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

        public IDeviceViewModel Parent
        {
            get
            {
                _parent.TryGetTarget(out var parent);
                return parent;
            }
        }

        internal AppItemViewModel(DeviceViewModel parent, IAudioDeviceSession session, bool isChild = false) : base(session)
        {
            IsExpanded = isChild;
            _session = session;
            _parent = new WeakReference<DeviceViewModel>(parent);
            _session.PropertyChanged += Session_PropertyChanged;

            if (_session.Children != null)
            {
                _session.Children.CollectionChanged += Children_CollectionChanged;
                ChildApps = new ObservableCollection<IAppItemViewModel>();
                foreach (var child in _session.Children)
                {
                    ChildApps.Add(new AppItemViewModel(parent, child, true));
                }
            }
        }

        private void Session_PropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(_session.DisplayName)) RaisePropertyChanged(nameof(DisplayName));
            else if (e.PropertyName == nameof(_session.IconPath)) RaisePropertyChanged(nameof(IconPath));
        }

        private void Children_CollectionChanged(object sender, NotifyCollectionChangedEventArgs e)
        {
            if (!_parent.TryGetTarget(out var parent) || ChildApps == null) return;

            if (e.Action == NotifyCollectionChangedAction.Add)
            {
                Debug.Assert(e.NewItems.Count == 1);
                ChildApps.Add(new AppItemViewModel(parent, (IAudioDeviceSession)e.NewItems[0], true));
                return;
            }

            if (e.Action == NotifyCollectionChangedAction.Remove)
            {
                Debug.Assert(e.OldItems.Count == 1);
                var id = ((IAudioDeviceSession)e.OldItems[0]).Id;
                for (var i = 0; i < ChildApps.Count; i++)
                {
                    if (ChildApps[i].Id != id) continue;
                    (ChildApps[i] as IDisposable)?.Dispose();
                    ChildApps.RemoveAt(i);
                    return;
                }
                return;
            }

            throw new NotImplementedException();
        }

        public void MoveToDevice(string id, bool hide) => ((IAudioDeviceSessionInternal)_session).MoveToDevice(id, hide);

        public override void UpdatePeakValueForeground()
        {
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) ChildApps[i].UpdatePeakValueForeground();
            }
            base.UpdatePeakValueForeground();
        }

        public void UpdatePeakValueBackground()
        {
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) ChildApps[i].UpdatePeakValueBackground();
            }
            ((IAudioDeviceSessionInternal)_session).UpdatePeakValueBackground();
        }

        public bool DoesGroupWith(IAppItemViewModel app) => AppId == app.AppId;

        public override void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _session.PropertyChanged -= Session_PropertyChanged;
            if (_session.Children != null) _session.Children.CollectionChanged -= Children_CollectionChanged;
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) (ChildApps[i] as IDisposable)?.Dispose();
            }
            base.Dispose();
        }

        public override string ToString() => IsMuted
            ? Properties.Resources.AppOrDeviceMutedFormatAccessibleText.Replace("{Name}", DisplayName)
            : Properties.Resources.AppOrDeviceFormatAccessibleText.Replace("{Name}", DisplayName).Replace("{Volume}", Volume.ToString());
    }
}
'@

Write-Text 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' @'
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
            app.Expired += OnAppExpired;
            foreach (var childApp in app.ChildApps)
            {
                ((IAudioDeviceManagerWindowsAudio)_deviceManager).UnhideSessionsForProcessId(_device.Id, childApp.ProcessId);
            }

            for (var i = 0; i < Apps.Count; i++)
            {
                if (Apps[i].DoesGroupWith(app)) return;
            }
            Apps.AddSorted(app, AppItemViewModel.CompareByExeName);
        }

        private void OnAppExpired(object sender, EventArgs e)
        {
            var app = (TemporaryAppItemViewModel)sender;
            if (!Apps.Contains(app)) return;
            app.Expired -= OnAppExpired;
            Apps.Remove(app);
        }

        internal void AppLeavingFromThisDevice(IAppItemViewModel app)
        {
            if (app is TemporaryAppItemViewModel) Apps.Remove(app);
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
'@

$collectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$collection = Read-Text $collectionPath
$collection = $collection.Replace('                        AllDevices.Remove(allExisting);', "                        allExisting.Dispose();`r`n                        AllDevices.Remove(allExisting);")
$collection = $collection.Replace('                    AllDevices.Clear();', "                    for (var i = 0; i < AllDevices.Count; i++) AllDevices[i].Dispose();`r`n                    AllDevices.Clear();")
Write-Text $collectionPath $collection

Assert-NotContains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' '~AudioSessionViewModel'
Assert-NotContains 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs' '~AppItemViewModel'
Assert-NotContains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' '~DeviceViewModel'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public override void Dispose()'
Assert-Contains $collectionPath 'allExisting.Dispose();'
