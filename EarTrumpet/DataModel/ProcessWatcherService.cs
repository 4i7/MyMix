using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;

namespace EarTrumpet.DataModel
{
    public class ProcessWatcherService
    {
        private sealed class CallbackRegistration
        {
            public readonly long Id;
            public readonly Action<int> Callback;
            public CallbackRegistration(long id, Action<int> callback) { Id = id; Callback = callback; }
        }

        private sealed class ProcessWatcherData
        {
            public int ProcessId;
            public readonly List<CallbackRegistration> QuitActions = new List<CallbackRegistration>();
            public Process Process;
            public EventHandler ExitedHandler;
        }

        private sealed class Registration : IDisposable
        {
            private readonly int _processId;
            private readonly long _registrationId;
            private int _disposed;
            public Registration(int processId, long registrationId) { _processId = processId; _registrationId = registrationId; }
            public void Dispose() { if (Interlocked.Exchange(ref _disposed, 1) == 0) UnwatchProcess(_processId, _registrationId); }
        }

        private sealed class EmptyRegistration : IDisposable
        {
            public static readonly EmptyRegistration Instance = new EmptyRegistration();
            private EmptyRegistration() { }
            public void Dispose() { }
        }

        private static readonly object s_lock = new object();
        private static readonly Dictionary<int, ProcessWatcherData> s_watchers = new Dictionary<int, ProcessWatcherData>();
        private static long s_nextRegistrationId;

        public static IDisposable WatchProcess(int processId, Action<int> processQuit)
        {
            if (processQuit == null) throw new ArgumentNullException(nameof(processQuit));
            var registrationId = Interlocked.Increment(ref s_nextRegistrationId);
            var callback = new CallbackRegistration(registrationId, processQuit);

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.QuitActions.Add(callback);
                    return new Registration(processId, registrationId);
                }
            }

            Process process;
            try { process = Process.GetProcessById(processId); }
            catch (ArgumentException) { return EmptyRegistration.Instance; }
            catch (InvalidOperationException) { return EmptyRegistration.Instance; }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService open failed for {processId}: {ex.Message}");
                return EmptyRegistration.Instance;
            }

            var data = new ProcessWatcherData { ProcessId = processId, Process = process };
            data.QuitActions.Add(callback);
            data.ExitedHandler = (_, __) => CompleteWatcher(data, true);
            process.Exited += data.ExitedHandler;

            var raced = false;
            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.QuitActions.Add(callback);
                    raced = true;
                }
                else
                {
                    s_watchers.Add(processId, data);
                }
            }

            if (raced)
            {
                DisposeProcess(data);
                return new Registration(processId, registrationId);
            }

            try { process.EnableRaisingEvents = true; }
            catch (InvalidOperationException ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                CompleteWatcher(data, false);
                return EmptyRegistration.Instance;
            }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                CompleteWatcher(data, false);
                return EmptyRegistration.Instance;
            }

            return new Registration(processId, registrationId);
        }

        private static void UnwatchProcess(int processId, long registrationId)
        {
            ProcessWatcherData toDispose = null;
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(processId, out var data)) return;
                for (var i = data.QuitActions.Count - 1; i >= 0; i--)
                {
                    if (data.QuitActions[i].Id == registrationId) { data.QuitActions.RemoveAt(i); break; }
                }
                if (data.QuitActions.Count == 0)
                {
                    s_watchers.Remove(processId);
                    toDispose = data;
                }
            }
            if (toDispose != null) DisposeProcess(toDispose);
        }

        private static void CompleteWatcher(ProcessWatcherData data, bool invokeCallbacks)
        {
            CallbackRegistration[] callbacks = null;
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data)) return;
                s_watchers.Remove(data.ProcessId);
                if (invokeCallbacks) callbacks = data.QuitActions.ToArray();
                data.QuitActions.Clear();
            }
            DisposeProcess(data);
            if (callbacks == null) return;
            for (var i = 0; i < callbacks.Length; i++)
            {
                try { callbacks[i].Callback(data.ProcessId); }
                catch (Exception ex) { Trace.WriteLine($"ProcessWatcherService callback failed: {ex}"); }
            }
        }

        private static void DisposeProcess(ProcessWatcherData data)
        {
            var process = data.Process;
            data.Process = null;
            var handler = data.ExitedHandler;
            data.ExitedHandler = null;
            if (process == null) return;
            try { if (handler != null) process.Exited -= handler; }
            catch (InvalidOperationException) { }
            finally { process.Dispose(); }
        }
    }
}