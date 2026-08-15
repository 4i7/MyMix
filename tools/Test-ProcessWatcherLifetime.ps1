#Requires -Version 5.1
[CmdletBinding()]
param([string]$Executable = '.\Build\Release\MyMix.exe', [switch]$X86Child)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitProcess -and -not $X86Child) {
    $x86 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $x86)) { throw '32-bit Windows PowerShell is required for the x86 MyMix lifetime test.' }
    & $x86 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Executable $Executable -X86Child
    exit $LASTEXITCODE
}

$exe = (Resolve-Path $Executable).Path
$assembly = [Reflection.Assembly]::LoadFrom($exe)
$type = $assembly.GetType('EarTrumpet.DataModel.ProcessWatcherService', $true)
$watch = $type.GetMethod('WatchProcess', [Reflection.BindingFlags]'Public,Static')
$watchers = $type.GetField('s_watchers', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
$sync = $type.GetField('s_lock', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
$flags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
$staticFlags = [Reflection.BindingFlags]'Public,NonPublic,Static'
if ($watch.ReturnType -ne [IDisposable]) { throw 'WatchProcess must return IDisposable.' }
if ($null -ne $type.GetField('s_threadRunning', $staticFlags)) { throw 'ProcessWatcherService still owns a dedicated watcher thread.' }
if ($null -ne $type.GetField('PollIntervalMilliseconds', $staticFlags)) { throw 'ProcessWatcherService still exposes a polling interval.' }

$helpers = @(Add-Type -PassThru -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.Runtime.Serialization;
using System.Threading;

public sealed class WatchCounter {
    private int _count;
    public int Value { get { return Volatile.Read(ref _count); } }
    public void Hit(int processId) { Interlocked.Increment(ref _count); }
}

public static class WatchRace {
    public static void Run(IDisposable registration, int processId) {
        Exception a = null, b = null;
        using (var process = Process.GetProcessById(processId))
        using (var gate = new ManualResetEvent(false)) {
            var t1 = new Thread(() => { gate.WaitOne(); try { registration.Dispose(); } catch (Exception ex) { a = ex; } });
            var t2 = new Thread(() => { gate.WaitOne(); try { if (!process.HasExited) process.Kill(); } catch (InvalidOperationException) { } catch (Exception ex) { b = ex; } });
            t1.Start(); t2.Start(); gate.Set(); t1.Join(); t2.Join();
        }
        if (a != null) throw new Exception("Dispose race failed", a);
        if (b != null) throw new Exception("Kill race failed", b);
    }
}

public sealed class DefaultInterfaceProxy : RealProxy {
    private readonly Dictionary<string, object> _values;

    public DefaultInterfaceProxy(Type interfaceType, Dictionary<string, object> values) : base(interfaceType) {
        _values = values;
    }

    public object Instance { get { return GetTransparentProxy(); } }

    public override IMessage Invoke(IMessage message) {
        var call = (IMethodCallMessage)message;
        var method = (MethodInfo)call.MethodBase;
        object value = null;
        if (!_values.TryGetValue(method.Name, out value) && method.ReturnType != typeof(void) && method.ReturnType.IsValueType) {
            value = Activator.CreateInstance(method.ReturnType);
        }
        return new ReturnMessage(value, null, 0, call.LogicalCallContext, call);
    }
}

public static class TemporaryVmStress {
    private const BindingFlags InstanceFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
    private const BindingFlags StaticFlags = BindingFlags.Static | BindingFlags.NonPublic;

    private static object Proxy(Type interfaceType, Dictionary<string, object> values) {
        return new DefaultInterfaceProxy(interfaceType, values).Instance;
    }

    private static int CallbackCount(IDictionary watchers, object sync, int processId) {
        lock (sync) {
            if (!watchers.Contains(processId)) return 0;
            var data = watchers[processId];
            var actions = (ICollection)data.GetType().GetField("QuitActions", InstanceFlags).GetValue(data);
            return actions.Count;
        }
    }

    private static void WaitForWatcherRemoval(IDictionary watchers, object sync, int processId) {
        var timer = Stopwatch.StartNew();
        while (timer.ElapsedMilliseconds < 10000) {
            lock (sync) {
                if (!watchers.Contains(processId)) return;
            }
            Thread.Sleep(25);
        }
        throw new Exception("Temporary VM stress left a process watcher behind.");
    }

    private static WeakReference CreateAndRelease(ConstructorInfo ctor, MethodInfo expire, MethodInfo dispose,
        object parent, object deviceManager, object app, bool useExpire) {
        var vm = ctor.Invoke(new object[] { parent, deviceManager, app, false });
        var weak = new WeakReference(vm);
        if (useExpire) expire.Invoke(vm, null);
        else dispose.Invoke(vm, null);
        dispose.Invoke(vm, null);
        return weak;
    }

    public static void Run(string assemblyPath, int processId, int iterations) {
        var assembly = Assembly.LoadFrom(assemblyPath);
        var watcherType = assembly.GetType("EarTrumpet.DataModel.ProcessWatcherService", true);
        var tempType = assembly.GetType("EarTrumpet.UI.ViewModels.TemporaryAppItemViewModel", true);
        var parentType = assembly.GetType("EarTrumpet.UI.ViewModels.DeviceCollectionViewModel", true);
        var appType = assembly.GetType("EarTrumpet.UI.ViewModels.IAppItemViewModel", true);
        var managerType = assembly.GetType("EarTrumpet.DataModel.Audio.IAudioDeviceManager", true);

        var watchers = (IDictionary)watcherType.GetField("s_watchers", StaticFlags).GetValue(null);
        var sync = watcherType.GetField("s_lock", StaticFlags).GetValue(null);
        var collectionType = typeof(ObservableCollection<>).MakeGenericType(appType);
        var emptyChildren = Activator.CreateInstance(collectionType);
        var childValues = new Dictionary<string, object>();
        childValues["get_ProcessId"] = processId;
        childValues["get_ChildApps"] = emptyChildren;
        var childApp = Proxy(appType, childValues);

        var children = Activator.CreateInstance(collectionType);
        collectionType.GetMethod("Add").Invoke(children, new object[] { childApp });
        var parentValues = new Dictionary<string, object>();
        parentValues["get_ProcessId"] = processId;
        parentValues["get_ChildApps"] = children;
        parentValues["get_Id"] = "mymix-lifetime-stress";
        parentValues["get_ExeName"] = "mymix-lifetime-stress.exe";
        parentValues["get_AppId"] = "mymix-lifetime-stress";
        parentValues["get_DisplayName"] = "MyMix Lifetime Stress";
        var app = Proxy(appType, parentValues);
        var deviceManager = Proxy(managerType, new Dictionary<string, object>());
        var parent = FormatterServices.GetUninitializedObject(parentType);

        ConstructorInfo ctor = null;
        foreach (var candidate in tempType.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic)) {
            if (candidate.GetParameters().Length == 4) { ctor = candidate; break; }
        }
        if (ctor == null) throw new Exception("TemporaryAppItemViewModel internal constructor was not found.");
        var expire = tempType.GetMethod("Expire", BindingFlags.Instance | BindingFlags.NonPublic);
        var dispose = tempType.GetMethod("Dispose", BindingFlags.Instance | BindingFlags.Public);
        if (expire == null || dispose == null) throw new Exception("TemporaryAppItemViewModel lifetime methods were not found.");

        var weakReferences = new List<WeakReference>(iterations);
        for (var i = 0; i < iterations; i++) {
            weakReferences.Add(CreateAndRelease(ctor, expire, dispose, parent, deviceManager, app, (i & 1) == 0));
            if ((i % 100) == 0 && CallbackCount(watchers, sync, processId) > 0) {
                throw new Exception("Temporary VM process-watch callbacks accumulated at iteration " + i + ".");
            }
        }

        if (CallbackCount(watchers, sync, processId) != 0) {
            throw new Exception("Temporary VM stress left callback registrations behind.");
        }
        WaitForWatcherRemoval(watchers, sync, processId);

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        var alive = 0;
        foreach (var weak in weakReferences) if (weak.IsAlive) alive++;
        if (alive != 0) throw new Exception("Disposed TemporaryAppItemViewModel instances retained after GC: " + alive + ".");
    }
}
'@)

$counterType = @($helpers | Where-Object Name -eq 'WatchCounter')[0]
$raceType = @($helpers | Where-Object Name -eq 'WatchRace')[0]
$tempStressType = @($helpers | Where-Object Name -eq 'TemporaryVmStress')[0]

function Assert([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
function Until([scriptblock]$test, [string]$message, [int]$ms = 6000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) { if (& $test) { return }; Start-Sleep -Milliseconds 20 }
    throw $message
}
function New-Process { Start-Process (Join-Path $env:WINDIR 'System32\PING.EXE') -ArgumentList '-t','127.0.0.1' -WindowStyle Hidden -PassThru }
function Stop-ProcessSafe($p) { if ($null -eq $p) { return }; try { if (-not $p.HasExited) { $p.Kill() }; $p.WaitForExit(5000) | Out-Null } catch { } finally { $p.Dispose() } }
function New-Counter { [Activator]::CreateInstance($counterType) }
function Register($p, $counter) {
    $callback = [Delegate]::CreateDelegate([Action[int]], $counter, $counterType.GetMethod('Hit'))
    [IDisposable]$watch.Invoke($null, @($p.Id, $callback))
}
function With-Lock([scriptblock]$body) { [Threading.Monitor]::Enter($sync); try { & $body } finally { [Threading.Monitor]::Exit($sync) } }
function Get-Data([int]$processId) { With-Lock { if ($watchers.ContainsKey($processId)) { $watchers[$processId] } else { $null } } }
function Callback-Count($data) { With-Lock { $data.GetType().GetField('QuitActions', $flags).GetValue($data).Count } }
function Process-Ref($data) { With-Lock { $data.GetType().GetField('Process', $flags).GetValue($data) } }
function Watcher-Count { With-Lock { $watchers.Count } }
function Gone([int]$processId, $data) {
    Until { $null -eq (Get-Data $processId) } "PID $processId watcher was not reclaimed."
    Until { $null -eq (Process-Ref $data) } "PID $processId Process object was not released."
}

# Multiple registrations share one event-driven process watcher and dispose independently.
$p = $null
try {
    $p = New-Process; $a = New-Counter; $b = New-Counter
    $ra = Register $p $a; $rb = Register $p $b; $data = Get-Data $p.Id
    Assert ($null -ne $data) 'Expected a watcher entry.'
    Assert ((Callback-Count $data) -eq 2) 'Expected two registrations.'
    $processField = $data.GetType().GetField('Process', $flags)
    Assert ($processField.FieldType -eq [Diagnostics.Process]) 'Watcher is not backed by System.Diagnostics.Process.'
    $ra.Dispose(); $ra.Dispose(); $ra.Dispose()
    Assert ((Callback-Count $data) -eq 1) 'Disposing A did not leave exactly B.'
    $p.Kill(); $p.WaitForExit(5000) | Out-Null
    Until { $b.Value -eq 1 } 'B was not called on process exit.'
    Assert ($a.Value -eq 0) 'Disposed callback A fired.'
    Assert ($b.Value -eq 1) 'Callback B fired more than once.'
    Gone $p.Id $data
    $rb.Dispose(); $rb.Dispose()
} finally { Stop-ProcessSafe $p }

# Full unregister must remove the CLR exit wait while the process remains alive.
$p = $null
try {
    $p = New-Process; $a = New-Counter; $b = New-Counter
    $ra = Register $p $a; $rb = Register $p $b; $data = Get-Data $p.Id
    $ra.Dispose(); $rb.Dispose(); $ra.Dispose(); $rb.Dispose()
    Assert ((Callback-Count $data) -eq 0) 'Full unregister did not reach zero callbacks.'
    Gone $p.Id $data
    Assert ($a.Value -eq 0 -and $b.Value -eq 0) 'Callback fired after full unregister.'
} finally { Stop-ProcessSafe $p }

# Repeated register/dispose on a long-lived PID must not retain Process objects or callbacks.
$p = $null
try {
    $p = New-Process; $c = New-Counter
    for ($i = 0; $i -lt 1000; $i++) {
        $r = Register $p $c
        $r.Dispose()
        if (($i % 100) -eq 0) { Until { (Watcher-Count) -eq 0 } "Watcher retained at iteration $i." 3000 }
    }
    Until { (Watcher-Count) -eq 0 } 'Registration stress left a watcher behind.'
    Assert ($c.Value -eq 0) 'Stress callback fired while process was alive.'
} finally { Stop-ProcessSafe $p }

# Actual temporary VMs must release process-watch tokens and become collectible.
$p = $null
try {
    $p = New-Process
    $tempStressType.GetMethod('Run').Invoke($null, @($exe, [int]$p.Id, 1000))
} finally { Stop-ProcessSafe $p }

# Exit and Dispose may race, but callback delivery must never duplicate and no watcher may survive.
$counters = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt 64; $i++) {
    $p = $null
    try {
        $p = New-Process; $c = New-Counter; $counters.Add($c); $r = Register $p $c
        $raceType.GetMethod('Run').Invoke($null, @($r, [int]$p.Id)); $p.WaitForExit(5000) | Out-Null
    } finally { Stop-ProcessSafe $p }
}
Until { (Watcher-Count) -eq 0 } 'Race test left watchers behind.' 10000
foreach ($c in $counters) { Assert ($c.Value -le 1) 'Race produced a duplicate callback.' }

Write-Host 'Event-driven ProcessWatcherService registration/lifetime/race/stress validation passed.' -ForegroundColor Green
