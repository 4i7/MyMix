# Final stability pass after the feature/size optimizers.
# Keep scalable single-handle polling, make process callbacks explicitly disposable, and make
# temporary app ownership deterministic so UI removal cannot leave process-watch roots behind.

$deviceCollectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$deviceCollection = Read-Text $deviceCollectionPath
$duplicateDisposePattern = '(?m)^(\s*for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);\r?\n)\s*for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);\r?\n'
$deviceCollection = [regex]::Replace($deviceCollection, $duplicateDisposePattern, '$1')
Write-Text $deviceCollectionPath $deviceCollection

# Temporary app VMs own every process-watch token they create. Expiration and all removal paths
# dispose those tokens, child event subscriptions, and child temporary VMs idempotently.
Write-Text 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' @'
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
'@

# DeviceViewModel owns a temporary VM only while it is actually present in Apps. Every path that
# declines, expires, or removes that VM disposes it and unregisters the Expired subscriber.
$devicePath = 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs'
$device = Read-Text $devicePath
$deviceLifetimePattern = '(?ms)        public void AppMovingToThisDevice\(TemporaryAppItemViewModel app\).*?        public void MakeDefaultDevice\(\)'
if ([regex]::Matches($device, $deviceLifetimePattern).Count -ne 1) {
    throw 'Could not locate the temporary-app ownership region in DeviceViewModel.cs.'
}
$deviceLifetimeReplacement = @'
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

        public void MakeDefaultDevice()
'@
$device = [regex]::Replace($device, $deviceLifetimePattern, $deviceLifetimeReplacement)
Write-Text $devicePath $device

# Do not allocate a temporary VM for a no-op device selection. If a real move allocates one but
# fails before ownership reaches the destination device, dispose it in finally.
$deviceCollection = Read-Text $deviceCollectionPath
$movePattern = '(?ms)        private void MoveAppToDeviceInternal\(IAppItemViewModel app, DeviceViewModel device\).*?        private void StartOrStopPeakTimer\(\)'
if ([regex]::Matches($deviceCollection, $movePattern).Count -ne 1) {
    throw 'Could not locate MoveAppToDeviceInternal in DeviceCollectionViewModel.cs.'
}
$moveReplacement = @'
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
'@
$deviceCollection = [regex]::Replace($deviceCollection, $movePattern, $moveReplacement)
Write-Text $deviceCollectionPath $deviceCollection

# Process callbacks are resources. Registration.Dispose only removes a callback and marks an empty
# watcher cancelled; only WatcherLoop removes published watchers and closes their process handles.
Write-Text 'EarTrumpet/DataModel/ProcessWatcherService.cs' @'
using EarTrumpet.Interop;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;

namespace EarTrumpet.DataModel
{
    // Tracks process lifetime for audio-session metadata. MyMix polls each process handle from
    // one background thread: no hard batch limit, no per-process worker thread, and sub-second
    // cleanup latency. Each callback has an explicit disposable registration lifetime.
    public class ProcessWatcherService
    {
        private sealed class CallbackRegistration
        {
            public readonly long Id;
            public readonly Action<int> Callback;

            public CallbackRegistration(long id, Action<int> callback)
            {
                Id = id;
                Callback = callback;
            }
        }

        private sealed class ProcessWatcherData
        {
            public int ProcessId;
            public readonly List<CallbackRegistration> QuitActions = new List<CallbackRegistration>();
            public IntPtr ProcessHandle;
            public bool Cancelled;
        }

        private sealed class Registration : IDisposable
        {
            private readonly int _processId;
            private readonly long _registrationId;
            private int _disposed;

            public Registration(int processId, long registrationId)
            {
                _processId = processId;
                _registrationId = registrationId;
            }

            public void Dispose()
            {
                if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
                UnwatchProcess(_processId, _registrationId);
            }
        }

        private sealed class EmptyRegistration : IDisposable
        {
            public static readonly EmptyRegistration Instance = new EmptyRegistration();
            private EmptyRegistration() { }
            public void Dispose() { }
        }

        private const int PollIntervalMilliseconds = 500;
        private static readonly object s_lock = new object();
        private static readonly Dictionary<int, ProcessWatcherData> s_watchers = new Dictionary<int, ProcessWatcherData>();
        private static long s_nextRegistrationId;
        private static bool s_threadRunning;

        public static IDisposable WatchProcess(int processId, Action<int> processQuit)
        {
            if (processQuit == null) throw new ArgumentNullException(nameof(processQuit));

            var registrationId = Interlocked.Increment(ref s_nextRegistrationId);
            var callbackRegistration = new CallbackRegistration(registrationId, processQuit);

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.Cancelled = false;
                    existing.QuitActions.Add(callbackRegistration);
                    return new Registration(processId, registrationId);
                }
            }

            var handle = Kernel32.OpenProcess(Kernel32.ProcessFlags.SYNCHRONIZE, false, processId);
            if (handle == IntPtr.Zero)
            {
                Trace.WriteLine($"ProcessWatcherService OpenProcess failed: {processId}");
                return EmptyRegistration.Instance;
            }

            if (Kernel32.WaitForSingleObject(handle, 0) != Kernel32.WAIT_TIMEOUT)
            {
                Kernel32.CloseHandle(handle);
                return EmptyRegistration.Instance;
            }

            var data = new ProcessWatcherData { ProcessId = processId, ProcessHandle = handle };
            data.QuitActions.Add(callbackRegistration);

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var raced))
                {
                    raced.Cancelled = false;
                    raced.QuitActions.Add(callbackRegistration);
                    Kernel32.CloseHandle(handle);
                    return new Registration(processId, registrationId);
                }

                s_watchers.Add(processId, data);
                if (!s_threadRunning)
                {
                    s_threadRunning = true;
                    var thread = new Thread(WatcherLoop)
                    {
                        IsBackground = true,
                        Name = "MyMix Process Watcher"
                    };
                    thread.Start();
                }
            }

            return new Registration(processId, registrationId);
        }

        private static void UnwatchProcess(int processId, long registrationId)
        {
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(processId, out var data)) return;

                data.QuitActions.RemoveAll(registration => registration.Id == registrationId);
                if (data.QuitActions.Count == 0)
                {
                    // Do not close here. WatcherLoop may already hold a snapshot containing this handle.
                    data.Cancelled = true;
                }
            }
        }

        private static void CloseWatcherHandle(ProcessWatcherData data)
        {
            var handle = data.ProcessHandle;
            if (handle == IntPtr.Zero) return;
            data.ProcessHandle = IntPtr.Zero;
            Kernel32.CloseHandle(handle);
        }

        private static void WatcherLoop()
        {
            while (true)
            {
                ProcessWatcherData[] snapshot;
                lock (s_lock)
                {
                    if (s_watchers.Count == 0)
                    {
                        s_threadRunning = false;
                        return;
                    }
                    snapshot = s_watchers.Values.ToArray();
                }

                for (var i = 0; i < snapshot.Length; i++)
                {
                    var data = snapshot[i];
                    var waitResult = Kernel32.WaitForSingleObject(data.ProcessHandle, 0);
                    CallbackRegistration[] callbacks = null;
                    var cancelled = false;
                    var shouldClose = false;

                    lock (s_lock)
                    {
                        if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data))
                        {
                            continue;
                        }

                        cancelled = data.Cancelled;
                        if (cancelled)
                        {
                            s_watchers.Remove(data.ProcessId);
                            shouldClose = true;
                        }
                        else if (waitResult != Kernel32.WAIT_TIMEOUT)
                        {
                            s_watchers.Remove(data.ProcessId);
                            shouldClose = true;
                            if (waitResult != Kernel32.WAIT_FAILED) callbacks = data.QuitActions.ToArray();
                        }
                    }

                    if (!shouldClose) continue;

                    try
                    {
                        if (!cancelled && waitResult == Kernel32.WAIT_FAILED)
                        {
                            Trace.WriteLine($"ProcessWatcherService wait failed: {data.ProcessId}");
                        }
                        else if (callbacks != null)
                        {
                            for (var callbackIndex = 0; callbackIndex < callbacks.Length; callbackIndex++)
                            {
                                try
                                {
                                    callbacks[callbackIndex].Callback(data.ProcessId);
                                }
                                catch (Exception ex)
                                {
                                    Trace.WriteLine($"ProcessWatcherService callback failed: {ex}");
                                }
                            }
                        }
                    }
                    finally
                    {
                        // Published handles are closed only by this watcher thread after snapshot use.
                        CloseWatcherHandle(data);
                    }
                }

                Thread.Sleep(PollIntervalMilliseconds);
            }
        }
    }
}
'@

Assert-NotContains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'Kernel32.WaitForMultipleObjects('
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'public static IDisposable WatchProcess'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'UnwatchProcess'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'public bool Cancelled;'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'CloseWatcherHandle(data);'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'PollIntervalMilliseconds = 500'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'callback failed'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' 'IAppItemViewModel, IDisposable'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' '_processWatchRegistrations'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' 'Interlocked.Exchange(ref _disposed, 1)'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'temporaryApp.Dispose();'
Assert-Contains $deviceCollectionPath 'TemporaryAppItemViewModel tempApp = null;'
Assert-Contains $deviceCollectionPath 'tempApp?.Dispose();'
Assert-NotContains $deviceCollectionPath "AllDevices[i].Dispose();`r`n                     for (var i = 0; i < AllDevices.Count; i++) AllDevices[i].Dispose();"
