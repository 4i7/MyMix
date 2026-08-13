# -----------------------------------------------------------------------------
# 10. Process metadata cache: multiple audio sessions from the same PID should not
#     repeat shell/process metadata lookup and process-watcher registration.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' @'
using EarTrumpet.Interop.Helpers;
using System;
using System.Collections.Concurrent;
using System.Threading;

namespace EarTrumpet.DataModel.AppInformation
{
    public class AppInformationFactory
    {
        private static readonly ConcurrentDictionary<int, Lazy<IAppInfo>> s_tracked = new ConcurrentDictionary<int, Lazy<IAppInfo>>();

        public static IAppInfo CreateForProcess(int processId, bool trackProcess = false)
        {
            if (!trackProcess || processId == 0)
            {
                return CreateCore(processId, trackProcess);
            }

            return s_tracked.GetOrAdd(processId, pid => new Lazy<IAppInfo>(
                () => CreateTracked(pid), LazyThreadSafetyMode.ExecutionAndPublication)).Value;
        }

        private static IAppInfo CreateTracked(int processId)
        {
            var info = CreateCore(processId, true);
            info.Stopped += _ =>
            {
                s_tracked.TryRemove(processId, out var ignored);
            };
            return info;
        }

        private static IAppInfo CreateCore(int processId, bool trackProcess)
        {
            if (processId == 0) return new Internal.SystemSoundsAppInfo();
            return Kernel32Helper.IsPackagedProcess(processId)
                ? (IAppInfo)new Internal.ModernAppInfo(processId, trackProcess)
                : new Internal.DesktopAppInfo(processId, trackProcess);
        }
    }
}
'@

Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ConcurrentDictionary<int, Lazy<IAppInfo>>'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'LazyThreadSafetyMode.ExecutionAndPublication'
