# Event-driven process exit can arrive immediately. Preserve a sticky one-shot Stopped event so
# AppInformationFactory and AudioDeviceSession cannot miss an exit between object construction and subscription.

function Add-StickyStoppedEvent([string]$RelativePath, [string]$NextMethodAnchor) {
    $text = Read-Text $RelativePath
    if ($text.Contains('private Action<IAppInfo> _stoppedHandlers;')) { return }

    $eventAnchor = '        public event Action<IAppInfo> Stopped;'
    if (-not $text.Contains($eventAnchor)) { throw ($RelativePath + ' Stopped event anchor was not found.') }

    $eventBlock = @'
        private readonly object _stoppedLock = new object();
        private Action<IAppInfo> _stoppedHandlers;
        private bool _isStopped;

        public event Action<IAppInfo> Stopped
        {
            add
            {
                if (value == null) return;
                var invokeNow = false;
                lock (_stoppedLock)
                {
                    if (_isStopped) invokeNow = true;
                    else _stoppedHandlers += value;
                }
                if (invokeNow) value(this);
            }
            remove
            {
                if (value == null) return;
                lock (_stoppedLock)
                {
                    _stoppedHandlers -= value;
                }
            }
        }
'@
    $text = $text.Replace($eventAnchor, $eventBlock)

    $oldWatch = 'ProcessWatcherService.WatchProcess(processId, (pid) => Stopped?.Invoke(this));'
    if (-not $text.Contains($oldWatch)) {
        $oldWatch = 'ProcessWatcherService.WatchProcess(processId, pid => Stopped?.Invoke(this));'
    }
    if (-not $text.Contains($oldWatch)) { throw ($RelativePath + ' process-watch callback anchor was not found.') }
    $text = $text.Replace($oldWatch, 'ProcessWatcherService.WatchProcess(processId, pid => NotifyStopped());')

    if (-not $text.Contains($NextMethodAnchor)) { throw ($RelativePath + ' next-method anchor was not found.') }
    $notify = @'
        private void NotifyStopped()
        {
            Action<IAppInfo> handlers;
            lock (_stoppedLock)
            {
                if (_isStopped) return;
                _isStopped = true;
                handlers = _stoppedHandlers;
                _stoppedHandlers = null;
            }
            handlers?.Invoke(this);
        }

'@
    $text = $text.Replace($NextMethodAnchor, $notify + $NextMethodAnchor)
    Write-Text $RelativePath $text
}

Add-StickyStoppedEvent 'EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs' '        private static bool TryGetExecutableNameViaNtByPid'
Add-StickyStoppedEvent 'EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs' '        private static string GetAppUserModelIdByPid'

Assert-Contains 'EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs' 'private Action<IAppInfo> _stoppedHandlers;'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs' 'pid => NotifyStopped()'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs' 'private Action<IAppInfo> _stoppedHandlers;'
Assert-Contains 'EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs' 'pid => NotifyStopped()'
