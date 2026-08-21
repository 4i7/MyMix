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
        internal enum ProcessWatchStatus
        {
            Watching,
            AlreadyExited,
            Unavailable
        }

        internal enum ProcessGenerationState
        {
            Current,
            Exited,
            Unknown
        }

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
            public Process Process;
            public EventHandler ExitedHandler;

            // Protected by s_lock.
            public bool IsPublished;
            public bool ExitObserved;
            public bool Completed;
        }

        internal sealed class ProcessWatchLease : IDisposable
        {
            private readonly ProcessWatcherData _data;
            private readonly long _registrationId;
            private readonly ProcessWatchStatus _status;
            private int _disposed;

            private ProcessWatchLease(ProcessWatchStatus status, ProcessWatcherData data, long registrationId)
            {
                _status = status;
                _data = data;
                _registrationId = registrationId;
            }

            internal static ProcessWatchLease Create(ProcessWatchStatus status, object data, long registrationId)
            {
                return new ProcessWatchLease(status, (ProcessWatcherData)data, registrationId);
            }

            internal ProcessWatchStatus Status => _status;

            internal ProcessGenerationState GenerationState
            {
                get
                {
                    switch (_status)
                    {
                        case ProcessWatchStatus.Watching:
                            return GetPublishedGenerationState(_data);
                        case ProcessWatchStatus.AlreadyExited:
                            return ProcessGenerationState.Exited;
                        default:
                            return ProcessGenerationState.Unknown;
                    }
                }
            }

            public void Dispose()
            {
                if (Interlocked.Exchange(ref _disposed, 1) != 0)
                {
                    return;
                }

                if (_status == ProcessWatchStatus.Watching)
                {
                    UnwatchProcess(_data, _registrationId);
                }
            }
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

        private static Func<int, Process> s_getProcessById = Process.GetProcessById;
        private static Action<Process> s_enableRaisingEvents = process => process.EnableRaisingEvents = true;

        public static IDisposable WatchProcess(int processId, Action<int> processQuit)
        {
            var lease = TryWatchProcess(processId, processQuit);
            if (lease.Status == ProcessWatchStatus.Watching)
            {
                return lease;
            }

            lease.Dispose();
            return EmptyRegistration.Instance;
        }

        internal static ProcessWatchLease TryWatchProcess(int processId, Action<int> processQuit)
        {
            if (processQuit == null)
            {
                throw new ArgumentNullException(nameof(processQuit));
            }

            var registrationId = Interlocked.Increment(ref s_nextRegistrationId);
            var callback = new CallbackRegistration(registrationId, processQuit);

            while (true)
            {
                ProcessWatcherData existing;
                lock (s_lock)
                {
                    s_watchers.TryGetValue(processId, out existing);
                }

                if (existing == null)
                {
                    break;
                }

                var existingState = GetPublishedGenerationState(existing);
                if (existingState == ProcessGenerationState.Current)
                {
                    lock (s_lock)
                    {
                        if (s_watchers.TryGetValue(processId, out var current)
                            && ReferenceEquals(current, existing)
                            && existing.IsPublished
                            && !existing.Completed)
                        {
                            existing.QuitActions.Add(callback);
                            return ProcessWatchLease.Create(ProcessWatchStatus.Watching, existing, registrationId);
                        }
                    }
                    continue;
                }

                if (existingState == ProcessGenerationState.Exited)
                {
                    CompletePublishedWatcher(existing, true);
                    continue;
                }

                return ProcessWatchLease.Create(ProcessWatchStatus.Unavailable, null, registrationId);
            }

            Process process;
            try
            {
                process = s_getProcessById(processId);
            }
            catch (ArgumentException)
            {
                return ProcessWatchLease.Create(ProcessWatchStatus.AlreadyExited, null, registrationId);
            }
            catch (InvalidOperationException)
            {
                return ProcessWatchLease.Create(ProcessWatchStatus.Unavailable, null, registrationId);
            }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService open failed for {processId}: {ex.Message}");
                return ProcessWatchLease.Create(ProcessWatchStatus.Unavailable, null, registrationId);
            }

            var data = new ProcessWatcherData { ProcessId = processId, Process = process };
            data.QuitActions.Add(callback);
            data.ExitedHandler = (_, __) => OnProcessExited(data);

            try
            {
                process.Exited += data.ExitedHandler;
            }
            catch
            {
                DisposeUnpublishedCandidate(data);
                throw;
            }

            try
            {
                s_enableRaisingEvents(process);
            }
            catch (InvalidOperationException ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                var status = ClassifyFailedCandidate(data);
                return ProcessWatchLease.Create(status, null, registrationId);
            }
            catch (Win32Exception ex)
            {
                Trace.WriteLine($"ProcessWatcherService enable failed for {processId}: {ex.Message}");
                var status = ClassifyFailedCandidate(data);
                return ProcessWatchLease.Create(status, null, registrationId);
            }
            catch
            {
                DisposeUnpublishedCandidate(data);
                throw;
            }

            while (true)
            {
                ProcessWatcherData winner;
                var candidateExited = false;

                lock (s_lock)
                {
                    if (data.ExitObserved)
                    {
                        data.Completed = true;
                        data.QuitActions.Clear();
                        candidateExited = true;
                        winner = null;
                    }
                    else if (!s_watchers.TryGetValue(processId, out winner))
                    {
                        s_watchers.Add(processId, data);
                        data.IsPublished = true;
                        return ProcessWatchLease.Create(ProcessWatchStatus.Watching, data, registrationId);
                    }
                }

                if (candidateExited)
                {
                    DisposeUnpublishedCandidate(data);
                    return ProcessWatchLease.Create(ProcessWatchStatus.AlreadyExited, null, registrationId);
                }

                var candidateState = GetUnpublishedCandidateState(data);
                if (candidateState == ProcessGenerationState.Exited)
                {
                    DisposeUnpublishedCandidate(data);
                    return ProcessWatchLease.Create(ProcessWatchStatus.AlreadyExited, null, registrationId);
                }
                if (candidateState == ProcessGenerationState.Unknown)
                {
                    DisposeUnpublishedCandidate(data);
                    return ProcessWatchLease.Create(ProcessWatchStatus.Unavailable, null, registrationId);
                }

                var winnerState = GetPublishedGenerationState(winner);
                if (winnerState == ProcessGenerationState.Exited)
                {
                    CompletePublishedWatcher(winner, true);
                    continue;
                }
                if (winnerState == ProcessGenerationState.Unknown)
                {
                    DisposeUnpublishedCandidate(data);
                    return ProcessWatchLease.Create(ProcessWatchStatus.Unavailable, null, registrationId);
                }

                var transferSucceeded = false;
                candidateExited = false;
                lock (s_lock)
                {
                    if (data.ExitObserved)
                    {
                        data.Completed = true;
                        data.QuitActions.Clear();
                        candidateExited = true;
                    }
                    else if (s_watchers.TryGetValue(processId, out var current)
                        && ReferenceEquals(current, winner)
                        && winner.IsPublished
                        && !winner.Completed)
                    {
                        winner.QuitActions.Add(callback);
                        data.QuitActions.Clear();
                        data.Completed = true;
                        transferSucceeded = true;
                    }
                }

                if (candidateExited)
                {
                    DisposeUnpublishedCandidate(data);
                    return ProcessWatchLease.Create(ProcessWatchStatus.AlreadyExited, null, registrationId);
                }
                if (!transferSucceeded)
                {
                    continue;
                }

                DisposeUnpublishedCandidate(data);
                return ProcessWatchLease.Create(ProcessWatchStatus.Watching, winner, registrationId);
            }
        }

        private static ProcessWatchStatus ClassifyFailedCandidate(ProcessWatcherData data)
        {
            DetachExitedHandler(data);

            var observedExit = false;
            lock (s_lock)
            {
                observedExit = data.ExitObserved;
                if (observedExit)
                {
                    data.Completed = true;
                    data.QuitActions.Clear();
                }
            }

            if (observedExit)
            {
                DisposeUnpublishedCandidateAfterDecision(data);
                return ProcessWatchStatus.AlreadyExited;
            }

            var probeSucceeded = false;
            var exited = false;
            Process process;
            lock (s_lock)
            {
                process = data.Process;
            }

            if (process != null)
            {
                try
                {
                    exited = process.HasExited;
                    probeSucceeded = true;
                }
                catch (ObjectDisposedException) { }
                catch (InvalidOperationException) { }
                catch (Win32Exception) { }
            }

            ProcessWatchStatus result;
            lock (s_lock)
            {
                result = data.ExitObserved || (probeSucceeded && exited)
                    ? ProcessWatchStatus.AlreadyExited
                    : ProcessWatchStatus.Unavailable;
                data.Completed = true;
                data.QuitActions.Clear();
            }

            DisposeUnpublishedCandidateAfterDecision(data);
            return result;
        }

        private static ProcessGenerationState GetUnpublishedCandidateState(ProcessWatcherData data)
        {
            Process process;
            lock (s_lock)
            {
                if (data.ExitObserved) return ProcessGenerationState.Exited;
                if (data.Completed || data.IsPublished) return ProcessGenerationState.Unknown;
                process = data.Process;
            }

            if (process == null) return ProcessGenerationState.Unknown;

            try
            {
                return process.HasExited ? ProcessGenerationState.Exited : ProcessGenerationState.Current;
            }
            catch (ObjectDisposedException) { return RecheckUnpublishedAfterProbeFailure(data); }
            catch (InvalidOperationException) { return RecheckUnpublishedAfterProbeFailure(data); }
            catch (Win32Exception) { return RecheckUnpublishedAfterProbeFailure(data); }
        }

        private static ProcessGenerationState RecheckUnpublishedAfterProbeFailure(ProcessWatcherData data)
        {
            lock (s_lock)
            {
                return data.ExitObserved ? ProcessGenerationState.Exited : ProcessGenerationState.Unknown;
            }
        }

        private static ProcessGenerationState GetPublishedGenerationState(ProcessWatcherData data)
        {
            if (data == null) return ProcessGenerationState.Unknown;

            Process process;
            lock (s_lock)
            {
                if (data.Completed) return ProcessGenerationState.Exited;
                if (!data.IsPublished) return ProcessGenerationState.Unknown;
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data))
                {
                    return ProcessGenerationState.Exited;
                }
                process = data.Process;
            }

            if (process == null) return ProcessGenerationState.Exited;

            try
            {
                return process.HasExited ? ProcessGenerationState.Exited : ProcessGenerationState.Current;
            }
            catch (ObjectDisposedException) { return RecheckPublishedAfterProbeFailure(data); }
            catch (InvalidOperationException) { return RecheckPublishedAfterProbeFailure(data); }
            catch (Win32Exception) { return ProcessGenerationState.Unknown; }
        }

        private static ProcessGenerationState RecheckPublishedAfterProbeFailure(ProcessWatcherData data)
        {
            lock (s_lock)
            {
                if (data.Completed || data.ExitObserved) return ProcessGenerationState.Exited;
                if (!data.IsPublished) return ProcessGenerationState.Unknown;
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data))
                {
                    return ProcessGenerationState.Exited;
                }
                return ProcessGenerationState.Unknown;
            }
        }

        private static void OnProcessExited(ProcessWatcherData data)
        {
            CallbackRegistration[] callbacks = null;
            var shouldDispose = false;
            lock (s_lock)
            {
                if (data.Completed) return;
                data.ExitObserved = true;
                if (!data.IsPublished) return;
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data)) return;
                s_watchers.Remove(data.ProcessId);
                data.IsPublished = false;
                data.Completed = true;
                callbacks = data.QuitActions.ToArray();
                data.QuitActions.Clear();
                shouldDispose = true;
            }

            if (!shouldDispose) return;
            DisposeProcess(data);
            InvokeCallbacks(data.ProcessId, callbacks);
        }

        private static void UnwatchProcess(ProcessWatcherData expected, long registrationId)
        {
            if (expected == null) return;

            ProcessWatcherData toDispose = null;
            lock (s_lock)
            {
                if (!s_watchers.TryGetValue(expected.ProcessId, out var current) || !ReferenceEquals(current, expected)) return;
                for (var i = expected.QuitActions.Count - 1; i >= 0; i--)
                {
                    if (expected.QuitActions[i].Id == registrationId)
                    {
                        expected.QuitActions.RemoveAt(i);
                        break;
                    }
                }
                if (expected.QuitActions.Count == 0)
                {
                    s_watchers.Remove(expected.ProcessId);
                    expected.Completed = true;
                    expected.IsPublished = false;
                    toDispose = expected;
                }
            }
            if (toDispose != null) DisposeProcess(toDispose);
        }

        private static void CompletePublishedWatcher(ProcessWatcherData data, bool invokeCallbacks)
        {
            CallbackRegistration[] callbacks = null;
            var shouldDispose = false;
            lock (s_lock)
            {
                if (data == null || data.Completed) return;
                data.ExitObserved = true;
                if (!data.IsPublished) return;
                if (!s_watchers.TryGetValue(data.ProcessId, out var current) || !ReferenceEquals(current, data)) return;
                s_watchers.Remove(data.ProcessId);
                data.IsPublished = false;
                data.Completed = true;
                if (invokeCallbacks) callbacks = data.QuitActions.ToArray();
                data.QuitActions.Clear();
                shouldDispose = true;
            }

            if (!shouldDispose) return;
            DisposeProcess(data);
            if (invokeCallbacks) InvokeCallbacks(data.ProcessId, callbacks);
        }

        private static void InvokeCallbacks(int processId, CallbackRegistration[] callbacks)
        {
            if (callbacks == null) return;
            for (var i = 0; i < callbacks.Length; i++)
            {
                try { callbacks[i].Callback(processId); }
                catch (Exception ex) { Trace.WriteLine($"ProcessWatcherService callback failed: {ex}"); }
            }
        }

        private static void DetachExitedHandler(ProcessWatcherData data)
        {
            Process process;
            EventHandler handler;
            lock (s_lock)
            {
                process = data.Process;
                handler = data.ExitedHandler;
                data.ExitedHandler = null;
            }

            if (process == null || handler == null) return;
            try { process.Exited -= handler; }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        private static void DisposeUnpublishedCandidate(ProcessWatcherData data)
        {
            lock (s_lock)
            {
                data.Completed = true;
                data.IsPublished = false;
                data.QuitActions.Clear();
            }
            DisposeUnpublishedCandidateAfterDecision(data);
        }

        private static void DisposeUnpublishedCandidateAfterDecision(ProcessWatcherData data)
        {
            DisposeProcess(data);
        }

        private static void DisposeProcess(ProcessWatcherData data)
        {
            Process process;
            EventHandler handler;
            lock (s_lock)
            {
                process = data.Process;
                data.Process = null;
                handler = data.ExitedHandler;
                data.ExitedHandler = null;
            }

            if (process == null) return;
            try
            {
                if (handler != null) process.Exited -= handler;
            }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
            finally { process.Dispose(); }
        }
    }
}
