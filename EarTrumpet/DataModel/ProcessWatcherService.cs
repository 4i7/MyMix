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
