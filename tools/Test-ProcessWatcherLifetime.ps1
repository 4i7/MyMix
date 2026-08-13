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

$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $Executable).Path)
$type = $assembly.GetType('EarTrumpet.DataModel.ProcessWatcherService', $true)
$watch = $type.GetMethod('WatchProcess', [Reflection.BindingFlags]'Public,Static')
$watchers = $type.GetField('s_watchers', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
$sync = $type.GetField('s_lock', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
$flags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
if ($watch.ReturnType -ne [IDisposable]) { throw 'WatchProcess must return IDisposable.' }

$helpers = @(Add-Type -PassThru -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Threading;
public sealed class WatchCounter {
    private int _count;
    public int Value { get { return Volatile.Read(ref _count); } }
    public void Hit(int processId) { Interlocked.Increment(ref _count); }
}
public static class WatchRace {
    public static void Run(IDisposable registration, Process process) {
        Exception a = null, b = null;
        using (var gate = new ManualResetEvent(false)) {
            var t1 = new Thread(() => { gate.WaitOne(); try { registration.Dispose(); } catch (Exception ex) { a = ex; } });
            var t2 = new Thread(() => { gate.WaitOne(); try { if (!process.HasExited) process.Kill(); } catch (InvalidOperationException) { } catch (Exception ex) { b = ex; } });
            t1.Start(); t2.Start(); gate.Set(); t1.Join(); t2.Join();
        }
        if (a != null) throw new Exception("Dispose race failed", a);
        if (b != null) throw new Exception("Kill race failed", b);
    }
}
'@)
$counterType = @($helpers | Where-Object Name -eq 'WatchCounter')[0]
$raceType = @($helpers | Where-Object Name -eq 'WatchRace')[0]

function Assert([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
function Until([scriptblock]$test, [string]$message, [int]$ms = 6000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) { if (& $test) { return }; Start-Sleep -Milliseconds 25 }
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
function Handle($data) { With-Lock { [IntPtr]$data.GetType().GetField('ProcessHandle', $flags).GetValue($data) } }
function Watcher-Count { With-Lock { $watchers.Count } }
function Gone([int]$processId, $data) {
    Until { $null -eq (Get-Data $processId) } "PID $processId watcher was not reclaimed."
    Until { (Handle $data) -eq [IntPtr]::Zero } "PID $processId process handle was not closed by the watcher thread."
}

# Same PID: dispose A, terminate process, only B fires once. Dispose is idempotent.
$p = $null
try {
    $p = New-Process; $a = New-Counter; $b = New-Counter
    $ra = Register $p $a; $rb = Register $p $b; $data = Get-Data $p.Id
    Assert ((Callback-Count $data) -eq 2) 'Expected two registrations.'
    $ra.Dispose(); $ra.Dispose(); $ra.Dispose()
    Assert ((Callback-Count $data) -eq 1) 'Disposing A did not leave exactly B.'
    $p.Kill(); $p.WaitForExit(5000) | Out-Null
    Until { $b.Value -eq 1 } 'B was not called on process exit.'
    Assert ($a.Value -eq 0) 'Disposed callback A fired.'; Assert ($b.Value -eq 1) 'Callback B fired more than once.'
    Gone $p.Id $data; $rb.Dispose(); $rb.Dispose()
} finally { Stop-ProcessSafe $p }

# Dispose every registration while process stays alive: zero callbacks, watcher reclaimed, handle zeroed.
$p = $null
try {
    $p = New-Process; $a = New-Counter; $b = New-Counter
    $ra = Register $p $a; $rb = Register $p $b; $data = Get-Data $p.Id
    $ra.Dispose(); $rb.Dispose(); $ra.Dispose(); $rb.Dispose()
    Assert ((Callback-Count $data) -eq 0) 'Full unregister did not reach zero callbacks.'
    Gone $p.Id $data; Assert ($a.Value -eq 0 -and $b.Value -eq 0) 'Callback fired after full unregister.'
} finally { Stop-ProcessSafe $p }

# 1000 create/dispose cycles against one long-lived PID must not accumulate callbacks.
$p = $null
try {
    $p = New-Process; $c = New-Counter
    for ($i = 0; $i -lt 1000; $i++) {
        $r = Register $p $c; $r.Dispose()
        if (($i % 100) -eq 0) { $d = Get-Data $p.Id; if ($null -ne $d) { Assert ((Callback-Count $d) -le 1) "Callback accumulation at iteration $i." } }
    }
    Until { (Watcher-Count) -eq 0 } 'Stress test left a watcher behind.'
    Assert ($c.Value -eq 0) 'Stress callback fired while process was alive.'
} finally { Stop-ProcessSafe $p }

# Race process exit against Dispose repeatedly; each registration may fire zero or once, never twice.
$counters = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt 64; $i++) {
    $p = $null
    try {
        $p = New-Process; $c = New-Counter; $counters.Add($c); $r = Register $p $c
        $raceType.GetMethod('Run').Invoke($null, @($r, $p)); $p.WaitForExit(5000) | Out-Null
    } finally { Stop-ProcessSafe $p }
}
Until { (Watcher-Count) -eq 0 } 'Race test left watchers behind.' 10000
foreach ($c in $counters) { Assert ($c.Value -le 1) 'Race produced a duplicate callback.' }

Write-Host 'ProcessWatcherService registration lifetime/race/stress validation passed.' -ForegroundColor Green
