#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Executable = '.\Build\Release\MyMix.exe',
    [switch]$X86Child
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitProcess -and -not $X86Child) {
    $x86PowerShell = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $x86PowerShell)) {
        throw '32-bit Windows PowerShell is required to load the x86 MyMix assembly.'
    }

    & $x86PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Executable $Executable -X86Child
    exit $LASTEXITCODE
}

$exe = (Resolve-Path -LiteralPath $Executable).Path
$assembly = [Reflection.Assembly]::LoadFrom($exe)
$watcherType = $assembly.GetType('EarTrumpet.DataModel.ProcessWatcherService', $true)
$watchMethod = $watcherType.GetMethod('WatchProcess', [Reflection.BindingFlags]'Public,Static')
$watchersField = $watcherType.GetField('s_watchers', [Reflection.BindingFlags]'NonPublic,Static')
$lockField = $watcherType.GetField('s_lock', [Reflection.BindingFlags]'NonPublic,Static')

if ($null -eq $watchMethod -or $watchMethod.ReturnType -ne [IDisposable]) {
    throw 'ProcessWatcherService.WatchProcess is not a public IDisposable registration API.'
}
if ($null -eq $watchersField -or $null -eq $lockField) {
    throw 'ProcessWatcherService lifetime test hooks could not be resolved by reflection.'
}

$probeTypes = @(Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Threading;

public sealed class MyMixProcessWatcherCounter
{
    private int _count;
    public int Value { get { return Volatile.Read(ref _count); } }
    public void OnQuit(int processId) { Interlocked.Increment(ref _count); }
}

public static class MyMixProcessWatcherRace
{
    public static void DisposeAndKill(IDisposable registration, Process process)
    {
        Exception disposeError = null;
        Exception killError = null;
        using (var gate = new ManualResetEvent(false))
        {
            var disposeThread = new Thread(() =>
            {
                gate.WaitOne();
                try { registration.Dispose(); }
                catch (Exception ex) { disposeError = ex; }
            });
            var killThread = new Thread(() =>
            {
                gate.WaitOne();
                try
                {
                    if (!process.HasExited) process.Kill();
                }
                catch (InvalidOperationException) { }
                catch (Exception ex) { killError = ex; }
            });

            disposeThread.Start();
            killThread.Start();
            gate.Set();
            disposeThread.Join();
            killThread.Join();
        }

        if (disposeError != null) throw new Exception("Registration.Dispose failed during race.", disposeError);
        if (killError != null) throw new Exception("Process.Kill failed during race.", killError);
    }
}
'@ -PassThru)

$counterType = @($probeTypes | Where-Object Name -eq 'MyMixProcessWatcherCounter')[0]
$raceType = @($probeTypes | Where-Object Name -eq 'MyMixProcessWatcherRace')[0]
$watchers = [Collections.IDictionary]$watchersField.GetValue($null)
$sync = $lockField.GetValue($null)
$nonPublicInstance = [Reflection.BindingFlags]'NonPublic,Public,Instance'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Wait-Until([scriptblock]$Condition, [string]$Message, [int]$TimeoutMilliseconds = 5000) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 25
    }
    throw $Message
}

function Start-WatchedProcess {
    $ping = Join-Path $env:WINDIR 'System32\PING.EXE'
    Start-Process -FilePath $ping -ArgumentList '-t','127.0.0.1' -WindowStyle Hidden -PassThru
}

function Stop-TestProcess([Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) { $Process.Kill() }
        $Process.WaitForExit(5000) | Out-Null
    }
    catch { }
    finally { $Process.Dispose() }
}

function New-Counter {
    [Activator]::CreateInstance($counterType)
}

function New-Callback($Counter) {
    [Delegate]::CreateDelegate([Action[int]], $Counter, $counterType.GetMethod('OnQuit'))
}

function Watch-Process([int]$ProcessId, $Counter) {
    [IDisposable]$watchMethod.Invoke($null, @($ProcessId, (New-Callback $Counter)))
}

function Get-WatcherCount {
    [Threading.Monitor]::Enter($sync)
    try {
        return $watchers.Count
    }
    finally {
        [Threading.Monitor]::Exit($sync)
    }
}

function Get-WatcherData([int]$ProcessId) {
    [Threading.Monitor]::Enter($sync)
    try {
        if (-not $watchers.Contains($ProcessId)) { return $null }
        return $watchers[$ProcessId]
    }
    finally {
        [Threading.Monitor]::Exit($sync)
    }
}

function Get-CallbackCount($Data) {
    [Threading.Monitor]::Enter($sync)
    try {
        $actions = $Data.GetType().GetField('QuitActions', $nonPublicInstance).GetValue($Data)
        return $actions.Count
    }
    finally {
        [Threading.Monitor]::Exit($sync)
    }
}

function Get-WatcherHandle($Data) {
    [Threading.Monitor]::Enter($sync)
    try {
        [IntPtr]$Data.GetType().GetField('ProcessHandle', $nonPublicInstance).GetValue($Data)
    }
    finally {
        [Threading.Monitor]::Exit($sync)
    }
}

function Assert-WatcherGone([int]$ProcessId, $Data) {
    Wait-Until { $null -eq (Get-WatcherData $ProcessId) } "Watcher for PID $ProcessId was not reclaimed."
    Wait-Until { (Get-WatcherHandle $Data) -eq [IntPtr]::Zero } "Watcher handle for PID $ProcessId was not closed by WatcherLoop."
}

# A/B registration removal: disposing A must leave B registered and only B may run on exit.
$process = $null
try {
    $process = Start-WatchedProcess
    $a = New-Counter
    $b = New-Counter
    $registrationA = Watch-Process $process.Id $a
    $registrationB = Watch-Process $process.Id $b
    $data = Get-WatcherData $process.Id
    Assert-True ($null -ne $data) 'Expected watcher data after A/B registration.'
    Assert-True ((Get-CallbackCount $data) -eq 2) 'Expected two callback registrations for the same PID.'

    $registrationA.Dispose()
    $registrationA.Dispose()
    $registrationA.Dispose()
    Assert-True ((Get-CallbackCount $data) -eq 1) 'Disposing callback A did not leave exactly callback B.'

    $process.Kill()
    $process.WaitForExit(5000) | Out-Null
    Wait-Until { $b.Value -eq 1 } 'Callback B was not invoked once after process exit.'
    Assert-True ($a.Value -eq 0) 'Disposed callback A was invoked after process exit.'
    Assert-True ($b.Value -eq 1) 'Callback B was invoked more than once.'
    Assert-WatcherGone $process.Id $data
    $registrationB.Dispose()
    $registrationB.Dispose()
}
finally {
    Stop-TestProcess $process
}

# All registrations removed: callback count reaches zero, watcher is reclaimed, handle becomes zero.
$process = $null
try {
    $process = Start-WatchedProcess
    $a = New-Counter
    $b = New-Counter
    $registrationA = Watch-Process $process.Id $a
    $registrationB = Watch-Process $process.Id $b
    $data = Get-WatcherData $process.Id
    Assert-True ((Get-CallbackCount $data) -eq 2) 'Expected two callbacks before full unregister.'

    $registrationA.Dispose()
    $registrationB.Dispose()
    $registrationA.Dispose()
    $registrationB.Dispose()
    Assert-True ((Get-CallbackCount $data) -eq 0) 'Full unregister did not reduce callback count to zero.'
    Assert-WatcherGone $process.Id $data
    Assert-True ($a.Value -eq 0 -and $b.Value -eq 0) 'A callback ran after all registrations were disposed.'
}
finally {
    Stop-TestProcess $process
}

# Lifetime stress: 1000 register/dispose cycles against one long-lived PID must not accumulate callbacks.
$process = $null
try {
    $process = Start-WatchedProcess
    $counter = New-Counter
    for ($i = 0; $i -lt 1000; $i++) {
        $registration = Watch-Process $process.Id $counter
        $registration.Dispose()
        if (($i % 100) -eq 0) {
            $data = Get-WatcherData $process.Id
            if ($null -ne $data) {
                Assert-True ((Get-CallbackCount $data) -le 1) "Callback registrations accumulated during stress iteration $i."
            }
        }
    }

    $data = Get-WatcherData $process.Id
    if ($null -ne $data) {
        Wait-Until { (Get-CallbackCount $data) -eq 0 } 'Stress test left callback registrations behind.'
        Assert-WatcherGone $process.Id $data
    }
    Assert-True ($counter.Value -eq 0) 'A callback ran while the stress-test process was still alive.'
}
finally {
    Stop-TestProcess $process
}

# Exit/unregister race: each registration may run zero or one time, never duplicate or crash.
$counters = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt 64; $i++) {
    $process = $null
    try {
        $process = Start-WatchedProcess
        $counter = New-Counter
        $counters.Add($counter)
        $registration = Watch-Process $process.Id $counter
        $raceType.GetMethod('DisposeAndKill').Invoke($null, @($registration, $process))
        $process.WaitForExit(5000) | Out-Null
    }
    finally {
        Stop-TestProcess $process
    }
}

Wait-Until { (Get-WatcherCount) -eq 0 } 'Race test left process watchers behind.' 10000
foreach ($counter in $counters) {
    Assert-True ($counter.Value -le 1) 'A process-exit/unregister race produced a duplicate callback.'
}

Write-Host 'ProcessWatcherService registration lifetime/race/stress validation passed.' -ForegroundColor Green
