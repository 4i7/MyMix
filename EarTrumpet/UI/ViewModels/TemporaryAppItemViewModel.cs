using EarTrumpet.DataModel;
using EarTrumpet.DataModel.Audio;
using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.Extensions;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Threading;
using System.Windows.Media;
using System.Windows.Threading;

namespace EarTrumpet.UI.ViewModels
{
    // This ViewModel is used in redirection scenarios. When we move a State=Inactive session to a device,
    // this serves as the visualization and data container for that app until a real session is created.
    public class TemporaryAppItemViewModel : BindableBase, IAppItemViewModel, IDisposable
    {
        public event EventHandler Expired;

        public string Id { get; }
        public bool IsMuted
        {
            get => ChildApps != null ? ChildApps[0].IsMuted : _isMuted;
            set
            {
                if (ChildApps != null)
                {
                    ChildApps[0].IsMuted = value;
                }
                else
                {
                    _isMuted = value;
                    RaisePropertyChanged(nameof(IsMuted));
                }
            }
        }
        public int Volume
        {
            get => ChildApps != null ? ChildApps[0].Volume : _volume;
            set
            {
                if (ChildApps != null)
                {
                    ChildApps[0].Volume = value;
                }
                else
                {
                    _volume = value;
                    RaisePropertyChanged(nameof(Volume));
                }
            }
        }
        public Color Background { get; }
        public ObservableCollection<IAppItemViewModel> ChildApps { get; }
        public string DisplayName { get; }
        public string ExeName { get; }
        public string AppId { get; }
        public char IconText { get; }
        public string IconPath { get; }
        public bool IsExpanded { get; }
        public bool IsDesktopApp { get; }
        public bool IsMovable { get; }
        public float PeakValue1 { get; }
        public string PersistedOutputDevice => ((IAudioDeviceManagerWindowsAudio)_deviceManager).GetDefaultEndPoint(ProcessId);
        public int ProcessId { get; }
        public IDeviceViewModel Parent { get; }

        private readonly IAudioDeviceManager _deviceManager;
        private readonly WeakReference<DeviceCollectionViewModel> _parent;
        private readonly Dispatcher _currentDispatcher = Dispatcher.CurrentDispatcher;
        private readonly List<IDisposable> _processWatchRegistrations = new List<IDisposable>();
        private int[] _processIds;
        private int _disposed;
        private int _expired;
        private int _volume;
        private bool _isMuted;

        internal TemporaryAppItemViewModel(DeviceCollectionViewModel parent, IAudioDeviceManager deviceManager, IAppItemViewModel app, bool isChild = false)
        {
            _parent = new WeakReference<DeviceCollectionViewModel>(parent);
            if (!isChild)
            {
                ChildApps = new ObservableCollection<IAppItemViewModel>();
                foreach (var childApp in app.ChildApps)
                {
                    var vm = new TemporaryAppItemViewModel(parent, deviceManager, childApp, true);
                    vm.PropertyChanged += ChildApp_PropertyChanged;
                    ChildApps.Add(vm);
                }
            }

            _deviceManager = deviceManager;
            Id = app.Id;
            _isMuted = app.IsMuted;
            _volume = app.Volume;
            Background = app.Background;
            DisplayName = app.DisplayName;
            ExeName = app.ExeName;
            AppId = app.AppId;
            IconText = app.IconText;
            IconPath = app.IconPath;
            IsDesktopApp = app.IsDesktopApp;
            IsMovable = app.IsMovable;
            IsExpanded = isChild;
            PeakValue1 = 0;
            ProcessId = app.ProcessId;
            Parent = app.Parent;

            if (ChildApps != null)
            {
                _processIds = ChildApps.Select(a => a.ProcessId).ToSet().ToArray();
            }
            else
            {
                _processIds = new[] { ProcessId };
            }

            foreach (var pid in _processIds)
            {
                _processWatchRegistrations.Add(ProcessWatcherService.WatchProcess(pid, OnProcessQuit));
            }

#if VSDEBUG
            Background = Colors.Red;
#endif
        }

        private bool IsDisposed => Interlocked.CompareExchange(ref _disposed, 0, 0) != 0;

        private void OnProcessQuit(int pidQuit)
        {
            if (IsDisposed) return;

            _currentDispatcher.BeginInvoke((Action)(() =>
            {
                if (IsDisposed) return;

                var newPids = _processIds.ToList();
                if (newPids.Contains(pidQuit))
                {
                    newPids.Remove(pidQuit);
                }
                _processIds = newPids.ToArray();

                if (_processIds.Length == 0)
                {
                    Expire();
                }
            }));
        }

        private void ChildApp_PropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (!IsDisposed)
            {
                RaisePropertyChanged(e.PropertyName);
            }
        }

        public bool DoesGroupWith(IAppItemViewModel app)
        {
            return ExeName == app.ExeName;
        }

        public void MoveToDevice(string id, bool hide)
        {
            if (IsDisposed) return;

            foreach (var pid in _processIds)
            {
                ((IAudioDeviceManagerWindowsAudio)_deviceManager).SetDefaultEndPoint(id, pid);
            }

            if (hide)
            {
                Expire();
            }
        }

        private void Expire()
        {
            if (Interlocked.Exchange(ref _expired, 1) != 0) return;

            try
            {
                Expired?.Invoke(this, EventArgs.Empty);
            }
            finally
            {
                Dispose();
            }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;

            foreach (var registration in _processWatchRegistrations)
            {
                registration.Dispose();
            }
            _processWatchRegistrations.Clear();

            if (ChildApps != null)
            {
                foreach (var child in ChildApps)
                {
                    child.PropertyChanged -= ChildApp_PropertyChanged;
                    (child as IDisposable)?.Dispose();
                }
            }
        }

        public void UpdatePeakValueBackground() { }
        public void UpdatePeakValueForeground() { }
    }
}