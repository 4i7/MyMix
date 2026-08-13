# Final stability pass after the feature/size optimizers.
# Keep this stage deliberately small: remove transform overlap and replace the inherited
# multi-handle wait design with scalable single-handle polling. A single low-frequency
# background thread remains responsive enough for removing audio sessions after process exit.

$deviceCollectionPath = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$deviceCollection = Read-Text $deviceCollectionPath
$duplicateDisposePattern = '(?m)^(\s*for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);\r?\n)\s*for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);\r?\n'
$deviceCollection = [regex]::Replace($deviceCollection, $duplicateDisposePattern, '$1')
Write-Text $deviceCollectionPath $deviceCollection

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
    // cleanup latency.
    public class ProcessWatcherService
    {
        private sealed class ProcessWatcherData
        {
            public int ProcessId;
            public readonly List<Action<int>> QuitActions = new List<Action<int>>();
            public IntPtr ProcessHandle;
        }

        private const int PollIntervalMilliseconds = 500;
        private static readonly object s_lock = new object();
        private static readonly Dictionary<int, ProcessWatcherData> s_watchers = new Dictionary<int, ProcessWatcherData>();
        private static bool s_threadRunning;

        public static void WatchProcess(int processId, Action<int> processQuit)
        {
            if (processQuit == null) throw new ArgumentNullException(nameof(processQuit));

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var existing))
                {
                    existing.QuitActions.Add(processQuit);
                    return;
                }
            }

            var handle = Kernel32.OpenProcess(Kernel32.ProcessFlags.SYNCHRONIZE, false, processId);
            if (handle == IntPtr.Zero)
            {
                Trace.WriteLine($"ProcessWatcherService OpenProcess failed: {processId}");
                return;
            }

            if (Kernel32.WaitForSingleObject(handle, 0) != Kernel32.WAIT_TIMEOUT)
            {
                Kernel32.CloseHandle(handle);
                return;
            }

            var data = new ProcessWatcherData { ProcessId = processId, ProcessHandle = handle };
            data.QuitActions.Add(processQuit);

            lock (s_lock)
            {
                if (s_watchers.TryGetValue(processId, out var raced))
                {
                    raced.QuitActions.Add(processQuit);
                    Kernel32.CloseHandle(handle);
                    return;
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
                    if (waitResult == Kernel32.WAIT_TIMEOUT) continue;

                    Action<int>[] callbacks = null;
                    lock (s_lock)
                    {
                        if (s_watchers.TryGetValue(data.ProcessId, out var current) && ReferenceEquals(current, data))
                        {
                            s_watchers.Remove(data.ProcessId);
                            callbacks = data.QuitActions.ToArray();
                        }
                    }

                    if (callbacks == null) continue;

                    try
                    {
                        if (waitResult == Kernel32.WAIT_FAILED)
                        {
                            Trace.WriteLine($"ProcessWatcherService wait failed: {data.ProcessId}");
                        }
                        else
                        {
                            for (var callbackIndex = 0; callbackIndex < callbacks.Length; callbackIndex++)
                            {
                                try
                                {
                                    callbacks[callbackIndex](data.ProcessId);
                                }
                                catch (Exception ex)
                                {
                                    // A background-thread callback must not become an unhandled
                                    // exception capable of terminating the whole desktop process.
                                    Trace.WriteLine($"ProcessWatcherService callback failed: {ex}");
                                }
                            }
                        }
                    }
                    finally
                    {
                        Kernel32.CloseHandle(data.ProcessHandle);
                    }
                }

                Thread.Sleep(PollIntervalMilliseconds);
            }
        }
    }
}
'@

Assert-NotContains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'Kernel32.WaitForMultipleObjects('
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'Kernel32.WaitForSingleObject(data.ProcessHandle, 0)'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'PollIntervalMilliseconds = 500'
Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'callback failed'
Assert-NotContains $deviceCollectionPath "AllDevices[i].Dispose();`r`n                     for (var i = 0; i < AllDevices.Count; i++) AllDevices[i].Dispose();"
