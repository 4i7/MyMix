#Requires -Version 5.1
[CmdletBinding()]
param([string]$Executable = '.\Build\Release\MyMix.exe', [switch]$X86Child)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitProcess -and -not $X86Child) {
    $x86 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $x86)) { throw '32-bit Windows PowerShell is required for the x86 MyMix AppInfo lifetime test.' }
    & $x86 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Executable $Executable -X86Child
    exit $LASTEXITCODE
}

$exe = (Resolve-Path $Executable).Path
$assembly = [Reflection.Assembly]::LoadFrom($exe)
$watcherType = $assembly.GetType('EarTrumpet.DataModel.ProcessWatcherService', $true)
$factoryType = $assembly.GetType('EarTrumpet.DataModel.AppInformation.AppInformationFactory', $true)
$staticFlags = [Reflection.BindingFlags]'Public,NonPublic,Static'
$instanceFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance'

$tryWatch = $watcherType.GetMethod('TryWatchProcess', $staticFlags)
$completePublished = $watcherType.GetMethod('CompletePublishedWatcher', $staticFlags)
$watchers = $watcherType.GetField('s_watchers', $staticFlags).GetValue($null)
$watcherLock = $watcherType.GetField('s_lock', $staticFlags).GetValue($null)
$getProcessField = $watcherType.GetField('s_getProcessById', $staticFlags)
$enableField = $watcherType.GetField('s_enableRaisingEvents', $staticFlags)
$originalGetProcess = $getProcessField.GetValue($null)
$originalEnable = $enableField.GetValue($null)
$watchersType = $watchers.GetType()
$watchersContainsKey = $watchersType.GetMethod('ContainsKey')
$watchersItem = $watchersType.GetProperty('Item')

$createForProcess = $factoryType.GetMethod('CreateForProcess', [Reflection.BindingFlags]'Public,Static')
$createTrackedLazy = $factoryType.GetMethod('CreateTrackedLazy', $staticFlags)
$tryRemoveExact = $factoryType.GetMethod('TryRemoveExact', $staticFlags)
$tracked = $factoryType.GetField('s_tracked', $staticFlags).GetValue($null)
$trackedType = $tracked.GetType()
$trackedContains = $trackedType.GetMethod('ContainsKey')
$trackedTryAdd = $trackedType.GetMethod('TryAdd')
$trackedItem = $trackedType.GetProperty('Item')

if ($null -eq $tryWatch -or $null -eq $completePublished) { throw 'Rich ProcessWatcherService API was not found.' }
if ($null -eq $getProcessField -or $null -eq $enableField) { throw 'Deterministic ProcessWatcherService seams were not found.' }
if ($null -eq $createTrackedLazy -or $null -eq $tryRemoveExact) { throw 'Generation-aware AppInformationFactory helpers were not found.' }

$helpers = @(Add-Type -PassThru -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Threading;

public sealed class LifetimeCounter {
    private int _count;
    public int Value { get { return Volatile.Read(ref _count); } }
    public void Hit(int processId) { Interlocked.Increment(ref _count); }
    public void HitObject(object value) { Interlocked.Increment(ref _count); }
}

public sealed class ReflectionInvocationThread {
    private readonly MethodInfo _method;
    private readonly int _processId;
    private readonly Action<int> _callback;
    private Thread _thread;

    public object Result { get; private set; }
    public Exception Error { get; private set; }

    public ReflectionInvocationThread(MethodInfo method, int processId, Action<int> callback) {
        _method = method;
        _processId = processId;
        _callback = callback;
    }

    public void Start() {
        _thread = new Thread(Run);
        _thread.IsBackground = true;
        _thread.Start();
    }

    private void Run() {
        try {
            Result = _method.Invoke(null, new object[] { _processId, _callback });
        }
        catch (TargetInvocationException ex) {
            Error = ex.InnerException ?? ex;
        }
        catch (Exception ex) {
            Error = ex;
        }
    }

    public bool Join(int milliseconds) {
        return _thread != null && _thread.Join(milliseconds);
    }
}

public static class LifetimeSeams {
    private static int _enableCount;
    private static int _getCount;

    public static readonly ManualResetEvent FirstEnableEntered = new ManualResetEvent(false);
    public static readonly ManualResetEvent SecondEnableEntered = new ManualResetEvent(false);
    public static readonly ManualResetEvent ReleaseFirstEnable = new ManualResetEvent(false);
    public static readonly ManualResetEvent GenerationAEnableEntered = new ManualResetEvent(false);
    public static readonly ManualResetEvent ReleaseGenerationA = new ManualResetEvent(false);

    public static int SequenceAId;
    public static int SequenceBId;
    public static int GenerationAId;

    public static void Reset() {
        Interlocked.Exchange(ref _enableCount, 0);
        Interlocked.Exchange(ref _getCount, 0);
        FirstEnableEntered.Reset();
        SecondEnableEntered.Reset();
        ReleaseFirstEnable.Reset();
        GenerationAEnableEntered.Reset();
        ReleaseGenerationA.Reset();
        SequenceAId = 0;
        SequenceBId = 0;
        GenerationAId = 0;
    }

    public static Process ThrowWin32Get(int processId) {
        throw new Win32Exception(5, "forced watcher open failure");
    }

    public static Process SequenceGet(int logicalProcessId) {
        var call = Interlocked.Increment(ref _getCount);
        var id = call == 1 ? SequenceAId : SequenceBId;
        return Process.GetProcessById(id);
    }

    public static void BlockingFailEnable(Process process) {
        var call = Interlocked.Increment(ref _enableCount);
        if (call == 1) {
            FirstEnableEntered.Set();
            ReleaseFirstEnable.WaitOne();
        }
        else {
            SecondEnableEntered.Set();
        }
        throw new Win32Exception(5, "forced enable failure");
    }

    public static void EnableThenExit(Process process) {
        process.EnableRaisingEvents = true;
        if (!process.HasExited) process.Kill();
        process.WaitForExit();
    }

    public static void GenerationEnable(Process process) {
        if (process.Id == GenerationAId) {
            GenerationAEnableEntered.Set();
            ReleaseGenerationA.WaitOne();
            if (!process.HasExited) process.Kill();
            process.WaitForExit();
            return;
        }

        process.EnableRaisingEvents = true;
    }
}
'@)

$counterType = @($helpers | Where-Object Name -eq 'LifetimeCounter')[0]
$invocationType = @($helpers | Where-Object Name -eq 'ReflectionInvocationThread')[0]
$seamType = @($helpers | Where-Object Name -eq 'LifetimeSeams')[0]

function Assert([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
function Until([scriptblock]$test, [string]$message, [int]$ms = 6000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
        if (& $test) { return }
        Start-Sleep -Milliseconds 20
    }
    throw $message
}
function New-Process { Start-Process (Join-Path $env:WINDIR 'System32\PING.EXE') -ArgumentList '-t','127.0.0.1' -WindowStyle Hidden -PassThru }
function Stop-ProcessSafe($p) {
    if ($null -eq $p) { return }
    try { if (-not $p.HasExited) { $p.Kill() }; $p.WaitForExit(5000) | Out-Null } catch { } finally { $p.Dispose() }
}
function New-Counter { [Activator]::CreateInstance($counterType) }
function New-Callback($counter) { [Delegate]::CreateDelegate([Action[int]], $counter, $counterType.GetMethod('Hit')) }
function Invoke-TryWatch([int]$processId, $counter) { $tryWatch.Invoke($null, @($processId, (New-Callback $counter))) }
function Get-Status($lease) { $lease.GetType().GetProperty('Status', $instanceFlags).GetValue($lease, $null).ToString() }
function Get-GenerationState($lease) { $lease.GetType().GetProperty('GenerationState', $instanceFlags).GetValue($lease, $null).ToString() }
function Dispose-Lease($lease) { if ($null -ne $lease) { ([IDisposable]$lease).Dispose() } }
function With-WatcherLock([scriptblock]$body) {
    [Threading.Monitor]::Enter($watcherLock)
    try { & $body } finally { [Threading.Monitor]::Exit($watcherLock) }
}
function Watcher-Contains([int]$processId) { With-WatcherLock { [bool]$watchersContainsKey.Invoke($watchers, @([int]$processId)) } }
function Get-Watcher([int]$processId) {
    With-WatcherLock {
        if ([bool]$watchersContainsKey.Invoke($watchers, @([int]$processId))) {
            $watchersItem.GetValue($watchers, @([int]$processId))
        }
        else { $null }
    }
}
function Watcher-CallbackCount($data) { With-WatcherLock { $data.GetType().GetField('QuitActions', $instanceFlags).GetValue($data).Count } }
function Tracked-Contains([int]$processId) { [bool]$trackedContains.Invoke($tracked, @([int]$processId)) }
function Tracked-Get([int]$processId) { if (Tracked-Contains $processId) { $trackedItem.GetValue($tracked, @([int]$processId)) } else { $null } }
function Factory-Create([int]$processId) { $createForProcess.Invoke($null, @([int]$processId, $true)) }
function Set-GetSeam([string]$methodName) {
    $delegate = [Delegate]::CreateDelegate($getProcessField.FieldType, $seamType.GetMethod($methodName))
    $getProcessField.SetValue($null, $delegate)
}
function Set-EnableSeam([string]$methodName) {
    $delegate = [Delegate]::CreateDelegate($enableField.FieldType, $seamType.GetMethod($methodName))
    $enableField.SetValue($null, $delegate)
}
function Restore-Seams {
    $getProcessField.SetValue($null, $originalGetProcess)
    $enableField.SetValue($null, $originalEnable)
    $seamType.GetMethod('Reset').Invoke($null, $null)
}
function New-Invocation([int]$processId, $counter) {
    [Activator]::CreateInstance($invocationType, @($tryWatch, $processId, (New-Callback $counter)))
}
function Entry-IsStopped($entry) { [bool]$entry.GetType().GetField('_isStopped', $instanceFlags).GetValue($entry) }
function Entry-Lease($entry) { $entry.GetType().GetField('_watchLease', $instanceFlags).GetValue($entry) }
function Entry-Evict($entry) { [Action]$entry.GetType().GetField('_evict', $instanceFlags).GetValue($entry) }

try {
    # Test A - faulted Lazy eviction: a failed construction must never poison the PID slot.
    $invalidPid = -1
    for ($i = 0; $i -lt 2; $i++) {
        $failed = $false
        try { Factory-Create $invalidPid | Out-Null } catch { $failed = $true }
        Assert $failed 'Test A expected invalid PID metadata construction to fail.'
        Assert (-not (Tracked-Contains $invalidPid)) 'Test A left a faulted Lazy in s_tracked.'
    }

    # Test B/J - exit after EnableRaisingEvents succeeds but before publication is latched, not dispatched synthetically.
    $p = $null; $lease = $null
    try {
        Restore-Seams
        $p = New-Process
        Set-EnableSeam 'EnableThenExit'
        $counter = New-Counter
        $lease = Invoke-TryWatch $p.Id $counter
        Assert ((Get-Status $lease) -eq 'AlreadyExited') 'Test B/J did not classify pre-publication exit as AlreadyExited.'
        Assert ($counter.Value -eq 0) 'Test B/J dispatched a synthetic callback for an unpublished candidate.'
        Assert (-not (Watcher-Contains $p.Id)) 'Test B/J published or retained an exited candidate.'
    } finally { Dispose-Lease $lease; Stop-ProcessSafe $p; Restore-Seams }

    # Test C/F - watcher operational failure is noncacheable/Unknown, but metadata remains usable and not stopped.
    $p = $null
    try {
        Restore-Seams
        $p = New-Process
        Set-GetSeam 'ThrowWin32Get'
        $counter = New-Counter
        $unavailableLease = Invoke-TryWatch $p.Id $counter
        Assert ((Get-Status $unavailableLease) -eq 'Unavailable') 'Test F expected Unavailable.'
        Assert ((Get-GenerationState $unavailableLease) -eq 'Unknown') 'Test F expected Unknown generation state.'
        Assert ($counter.Value -eq 0) 'Test F fired a callback for Unavailable.'
        Dispose-Lease $unavailableLease

        $entry = Factory-Create $p.Id
        Assert (-not [string]::IsNullOrWhiteSpace([string]$entry.ExeName)) 'Test C metadata was not usable after watcher failure.'
        Assert (-not (Tracked-Contains $p.Id)) 'Test C retained an unwatchable AppInfo in s_tracked.'
        Assert (-not (Entry-IsStopped $entry)) 'Test C/F converted Unavailable into Stopped.'
        Assert (-not $p.HasExited) 'Test C/F terminated the live metadata process.'
    } finally { Stop-ProcessSafe $p; Restore-Seams }

    # Test D - an old Entry eviction closure must not delete a replacement Lazy for the same PID.
    $p = $null
    try {
        Restore-Seams
        $p = New-Process
        $oldEntry = Factory-Create $p.Id
        $oldLazy = Tracked-Get $p.Id
        Assert ($null -ne $oldLazy) 'Test D did not create the original tracked Lazy.'
        Assert ([bool]$tryRemoveExact.Invoke($null, @([int]$p.Id, $oldLazy))) 'Test D could not exact-remove the old Lazy.'
        $newLazy = $createTrackedLazy.Invoke($null, @([int]$p.Id))
        Assert ([bool]$trackedTryAdd.Invoke($tracked, @([int]$p.Id, $newLazy))) 'Test D could not install the replacement Lazy.'
        (Entry-Evict $oldEntry).Invoke()
        $currentLazy = Tracked-Get $p.Id
        Assert ([object]::ReferenceEquals($currentLazy, $newLazy)) 'Test D old Entry deleted the replacement Lazy.'
        $tryRemoveExact.Invoke($null, @([int]$p.Id, $newLazy)) | Out-Null
    } finally { Stop-ProcessSafe $p; Restore-Seams }

    # Test E - a completed watcher makes an old cache hit stale even if its AppInfo callback has not evicted yet.
    $p = $null; $freshEntry = $null
    try {
        Restore-Seams
        $p = New-Process
        $oldEntry = Factory-Create $p.Id
        $oldLease = Entry-Lease $oldEntry
        $oldData = $oldLease.GetType().GetField('_data', $instanceFlags).GetValue($oldLease)
        $completePublished.Invoke($null, @($oldData, $false)) | Out-Null
        Assert (Tracked-Contains $p.Id) 'Test E setup unexpectedly evicted the old cache entry.'
        $freshEntry = Factory-Create $p.Id
        Assert (-not [object]::ReferenceEquals($freshEntry, $oldEntry)) 'Test E reused a completed generation as Current.'
        Assert (Entry-IsStopped $oldEntry) 'Test E stale validation did not make the old Entry sticky-stopped.'
    } finally { Stop-ProcessSafe $p; Restore-Seams }

    # Test G - disposing an old generation lease cannot unregister a replacement watcher.
    $p = $null; $oldLease = $null; $newLease = $null
    try {
        Restore-Seams
        $p = New-Process
        $oldCounter = New-Counter
        $oldLease = Invoke-TryWatch $p.Id $oldCounter
        $oldData = Get-Watcher $p.Id
        Assert ($null -ne $oldData) 'Test G old watcher was not published.'
        $completePublished.Invoke($null, @($oldData, $false)) | Out-Null
        Assert (-not (Watcher-Contains $p.Id)) 'Test G old watcher completion did not remove the old data.'

        $newCounter = New-Counter
        $newLease = Invoke-TryWatch $p.Id $newCounter
        $newData = Get-Watcher $p.Id
        Assert ($null -ne $newData) 'Test G replacement watcher was not published.'
        Dispose-Lease $oldLease; $oldLease = $null
        Assert ([object]::ReferenceEquals((Get-Watcher $p.Id), $newData)) 'Test G old lease removed the replacement watcher.'
        Assert ((Watcher-CallbackCount $newData) -eq 1) 'Test G old lease damaged replacement callbacks.'
    } finally { Dispose-Lease $oldLease; Dispose-Lease $newLease; Stop-ProcessSafe $p; Restore-Seams }

    # Test H - Stopped is sticky when process exit wins the construction/subscription race.
    $p = $null
    try {
        Restore-Seams
        $p = New-Process
        $entry = Factory-Create $p.Id
        $p.Kill(); $p.WaitForExit(5000) | Out-Null
        Until { Entry-IsStopped $entry } 'Test H Entry did not become stopped.'
        $appCounter = New-Counter
        $stoppedEvent = $entry.GetType().GetEvent('Stopped')
        $handler = [Delegate]::CreateDelegate($stoppedEvent.EventHandlerType, $appCounter, $counterType.GetMethod('HitObject'))
        $stoppedEvent.AddEventHandler($entry, $handler)
        Assert ($appCounter.Value -eq 1) 'Test H late Stopped subscriber was not invoked immediately once.'
        $stoppedEvent.RemoveEventHandler($entry, $handler)
    } finally { Stop-ProcessSafe $p; Restore-Seams }

    # Test I - an unpublished candidate must not be visible/shared while EnableRaisingEvents is unresolved.
    $p = $null; $t1 = $null; $t2 = $null
    try {
        Restore-Seams
        $p = New-Process
        Set-EnableSeam 'BlockingFailEnable'
        $c1 = New-Counter; $c2 = New-Counter
        $t1 = New-Invocation $p.Id $c1
        $t1.Start()
        Assert ($seamType.GetField('FirstEnableEntered').GetValue($null).WaitOne(5000)) 'Test I T1 never entered EnableRaisingEvents.'
        Assert (-not (Watcher-Contains $p.Id)) 'Test I published T1 before EnableRaisingEvents succeeded.'

        $t2 = New-Invocation $p.Id $c2
        $t2.Start()
        Assert ($seamType.GetField('SecondEnableEntered').GetValue($null).WaitOne(5000)) 'Test I T2 reused T1 instead of attempting its own establishment.'
        Assert ($t2.Join(5000)) 'Test I T2 did not finish its forced enable failure.'
        if ($null -ne $t2.Error) { throw $t2.Error }
        Assert ((Get-Status $t2.Result) -ne 'Watching') 'Test I T2 returned Watching before successful establishment.'
        Assert (-not (Watcher-Contains $p.Id)) 'Test I retained a failed candidate.'

        $seamType.GetField('ReleaseFirstEnable').GetValue($null).Set() | Out-Null
        Assert ($t1.Join(5000)) 'Test I T1 did not finish.'
        if ($null -ne $t1.Error) { throw $t1.Error }
        Assert ((Get-Status $t1.Result) -ne 'Watching') 'Test I T1 returned Watching after forced enable failure.'
        Assert ((Get-GenerationState $t1.Result) -ne 'Exited') 'Test I classified operational enable failure as Exited.'
        Assert ((Get-GenerationState $t2.Result) -ne 'Exited') 'Test I classified T2 operational enable failure as Exited.'
        Assert ($c1.Value -eq 0 -and $c2.Value -eq 0) 'Test I fired a callback on enable failure.'
        Assert (-not $p.HasExited) 'Test I terminated the live child.'
    } finally {
        if ($null -ne $t1 -and $null -ne $t1.Result) { Dispose-Lease $t1.Result }
        if ($null -ne $t2 -and $null -ne $t2.Result) { Dispose-Lease $t2.Result }
        $seamType.GetField('ReleaseFirstEnable').GetValue($null).Set() | Out-Null
        Stop-ProcessSafe $p
        Restore-Seams
    }

    # Test K - an exited candidate generation cannot transfer its callback to a different current winner generation.
    $a = $null; $b = $null; $t1 = $null; $t2 = $null
    try {
        Restore-Seams
        $a = New-Process
        $b = New-Process
        $logicalPid = 424242
        $seamType.GetField('SequenceAId').SetValue($null, [int]$a.Id)
        $seamType.GetField('SequenceBId').SetValue($null, [int]$b.Id)
        $seamType.GetField('GenerationAId').SetValue($null, [int]$a.Id)
        Set-GetSeam 'SequenceGet'
        Set-EnableSeam 'GenerationEnable'

        $aCounter = New-Counter; $bCounter = New-Counter
        $t1 = New-Invocation $logicalPid $aCounter
        $t1.Start()
        Assert ($seamType.GetField('GenerationAEnableEntered').GetValue($null).WaitOne(5000)) 'Test K candidate A did not reach its enable seam.'
        Assert (-not (Watcher-Contains $logicalPid)) 'Test K published candidate A before enable returned.'

        $t2 = New-Invocation $logicalPid $bCounter
        $t2.Start()
        Assert ($t2.Join(5000)) 'Test K winner B did not finish establishment.'
        if ($null -ne $t2.Error) { throw $t2.Error }
        Assert ((Get-Status $t2.Result) -eq 'Watching') 'Test K winner B was not Watching.'
        $winner = Get-Watcher $logicalPid
        Assert ($null -ne $winner) 'Test K winner B was not published.'
        Assert ((Watcher-CallbackCount $winner) -eq 1) 'Test K winner B callback list was not clean before A resumed.'

        $seamType.GetField('ReleaseGenerationA').GetValue($null).Set() | Out-Null
        Assert ($t1.Join(5000)) 'Test K candidate A did not finish.'
        if ($null -ne $t1.Error) { throw $t1.Error }
        Assert ((Get-Status $t1.Result) -eq 'AlreadyExited') 'Test K exited candidate A was not classified AlreadyExited.'
        Assert ([object]::ReferenceEquals((Get-Watcher $logicalPid), $winner)) 'Test K candidate A disturbed winner B.'
        Assert ((Watcher-CallbackCount $winner) -eq 1) 'Test K transferred A callback into winner B.'
        Assert ($aCounter.Value -eq 0) 'Test K dispatched candidate A callback.'

        $b.Kill(); $b.WaitForExit(5000) | Out-Null
        Until { $bCounter.Value -eq 1 } 'Test K winner B callback did not fire.'
        Assert ($aCounter.Value -eq 0) 'Test K A callback fired when winner B exited.'
    } finally {
        if ($null -ne $t1 -and $null -ne $t1.Result) { Dispose-Lease $t1.Result }
        if ($null -ne $t2 -and $null -ne $t2.Result) { Dispose-Lease $t2.Result }
        $seamType.GetField('ReleaseGenerationA').GetValue($null).Set() | Out-Null
        Stop-ProcessSafe $a
        Stop-ProcessSafe $b
        Restore-Seams
    }

    Write-Host 'AppInfo cache/process-generation lifecycle validation passed.' -ForegroundColor Green
}
finally {
    Restore-Seams
}
