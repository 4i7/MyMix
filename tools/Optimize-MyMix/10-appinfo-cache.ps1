# -----------------------------------------------------------------------------
# 10. Process metadata cache: cache only a verified current process generation.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' @'
using EarTrumpet.Interop.Helpers;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;

namespace EarTrumpet.DataModel.AppInformation
{
    public class AppInformationFactory
    {
        private enum EntryValidationState
        {
            Current,
            Stopped,
            Unverifiable
        }

        private sealed class ProcessAppInfoEntry : IAppInfo
        {
            private readonly int _processId;
            private readonly Action _evict;
            private readonly object _stoppedLock = new object();
            private readonly IAppInfo _inner;
            private readonly ProcessWatcherService.ProcessWatchLease _watchLease;

            private Action<IAppInfo> _stoppedHandlers;
            private bool _isStopped;

            public ProcessAppInfoEntry(int processId, Action evict)
            {
                _processId = processId;
                _evict = evict;
                _watchLease = ProcessWatcherService.TryWatchProcess(processId, OnProcessQuit);

                try
                {
                    _inner = CreateCore(processId, false);
                }
                catch
                {
                    _watchLease.Dispose();
                    throw;
                }

                switch (_watchLease.Status)
                {
                    case ProcessWatcherService.ProcessWatchStatus.Watching:
                        if (_watchLease.GenerationState == ProcessWatcherService.ProcessGenerationState.Exited)
                        {
                            NotifyStopped();
                        }
                        break;
                    case ProcessWatcherService.ProcessWatchStatus.AlreadyExited:
                        NotifyStopped();
                        break;
                }
            }

            public event Action<IAppInfo> Stopped
            {
                add
                {
                    if (value == null)
                    {
                        return;
                    }

                    var invokeNow = false;
                    lock (_stoppedLock)
                    {
                        if (_isStopped)
                        {
                            invokeNow = true;
                        }
                        else
                        {
                            _stoppedHandlers += value;
                        }
                    }

                    if (invokeNow)
                    {
                        value(this);
                    }
                }
                remove
                {
                    if (value == null)
                    {
                        return;
                    }

                    lock (_stoppedLock)
                    {
                        _stoppedHandlers -= value;
                    }
                }
            }

            public string ExeName => _inner.ExeName;
            public string DisplayName => _inner.DisplayName;
            public string PackageInstallPath => _inner.PackageInstallPath;
            public string SmallLogoPath => _inner.SmallLogoPath;
            public bool IsDesktopApp => _inner.IsDesktopApp;

            public EntryValidationState ValidateForCacheUse()
            {
                if (_watchLease.Status == ProcessWatcherService.ProcessWatchStatus.AlreadyExited)
                {
                    NotifyStopped();
                    return EntryValidationState.Stopped;
                }

                if (_watchLease.Status == ProcessWatcherService.ProcessWatchStatus.Unavailable)
                {
                    return EntryValidationState.Unverifiable;
                }

                switch (_watchLease.GenerationState)
                {
                    case ProcessWatcherService.ProcessGenerationState.Current:
                        return EntryValidationState.Current;
                    case ProcessWatcherService.ProcessGenerationState.Exited:
                        NotifyStopped();
                        _watchLease.Dispose();
                        return EntryValidationState.Stopped;
                    default:
                        return EntryValidationState.Unverifiable;
                }
            }

            private void OnProcessQuit(int processId)
            {
                if (processId == _processId)
                {
                    NotifyStopped();
                }
            }

            private void NotifyStopped()
            {
                Action<IAppInfo> handlers;

                _evict?.Invoke();

                lock (_stoppedLock)
                {
                    if (_isStopped)
                    {
                        return;
                    }

                    _isStopped = true;
                    handlers = _stoppedHandlers;
                    _stoppedHandlers = null;
                }

                handlers?.Invoke(this);
            }
        }

        private static readonly ConcurrentDictionary<int, Lazy<ProcessAppInfoEntry>> s_tracked =
            new ConcurrentDictionary<int, Lazy<ProcessAppInfoEntry>>();

        public static IAppInfo CreateForProcess(int processId, bool trackProcess = false)
        {
            if (!trackProcess || processId == 0)
            {
                return CreateCore(processId, trackProcess);
            }

            while (true)
            {
                var candidateLazy = CreateTrackedLazy(processId);
                var actualLazy = s_tracked.GetOrAdd(processId, candidateLazy);

                ProcessAppInfoEntry entry;
                try
                {
                    entry = actualLazy.Value;
                }
                catch
                {
                    TryRemoveExact(processId, actualLazy);
                    throw;
                }

                if (entry.ValidateForCacheUse() == EntryValidationState.Current)
                {
                    return entry;
                }

                TryRemoveExact(processId, actualLazy);

                if (ReferenceEquals(actualLazy, candidateLazy))
                {
                    return entry;
                }
            }
        }

        private static Lazy<ProcessAppInfoEntry> CreateTrackedLazy(int processId)
        {
            Lazy<ProcessAppInfoEntry> lazy = null;
            lazy = new Lazy<ProcessAppInfoEntry>(
                () => new ProcessAppInfoEntry(
                    processId,
                    () => TryRemoveExact(processId, lazy)),
                LazyThreadSafetyMode.ExecutionAndPublication);
            return lazy;
        }

        private static bool TryRemoveExact(int processId, Lazy<ProcessAppInfoEntry> lazy)
        {
            return ((ICollection<KeyValuePair<int, Lazy<ProcessAppInfoEntry>>>)s_tracked)
                .Remove(new KeyValuePair<int, Lazy<ProcessAppInfoEntry>>(processId, lazy));
        }

        private static IAppInfo CreateCore(int processId, bool trackProcess)
        {
            if (processId == 0)
            {
                return new Internal.SystemSoundsAppInfo();
            }

            return Kernel32Helper.IsPackagedProcess(processId)
                ? (IAppInfo)new Internal.ModernAppInfo(processId, trackProcess)
                : new Internal.DesktopAppInfo(processId, trackProcess);
        }
    }
}
'@

Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ConcurrentDictionary<int, Lazy<ProcessAppInfoEntry>>'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'LazyThreadSafetyMode.ExecutionAndPublication'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ICollection<KeyValuePair<int, Lazy<ProcessAppInfoEntry>>>'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ReferenceEquals(actualLazy, candidateLazy)'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ProcessWatcherService.TryWatchProcess'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'CreateCore(processId, false)'
Assert-NotContains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'PublicationOnly'
