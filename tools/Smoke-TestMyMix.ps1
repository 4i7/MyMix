#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Executable = '.\Build\Release\MyMix.exe',
    [int]$TimeoutMilliseconds = 15000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$exe = (Resolve-Path -LiteralPath $Executable).Path
$started = Get-Date
$env:MYMIX_MUTEX_SUFFIX = "ci-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT-$([Guid]::NewGuid().ToString('N'))"

function Write-RelevantApplicationEvents([DateTime]$Since, [int]$ProcessId) {
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $Since.AddSeconds(-2) } -ErrorAction Stop |
            Where-Object {
                $_.ProviderName -in @('.NET Runtime', 'Application Error', 'Windows Error Reporting') -and
                ($_.Message -match 'MyMix' -or $_.Message -match [regex]::Escape($ProcessId.ToString()))
            } |
            Select-Object -First 8)

        if ($events.Count -eq 0) {
            Write-Host 'No matching .NET/Application Error event was found.'
            return
        }

        Write-Host 'Relevant Windows Application log entries:'
        foreach ($event in $events) {
            Write-Host ('--- {0:u} [{1}] Event {2}' -f $event.TimeCreated, $event.ProviderName, $event.Id)
            Write-Host $event.Message
        }
    }
    catch {
        Write-Warning "Could not query the Windows Application event log: $($_.Exception.Message)"
    }
}

$process = Start-Process -FilePath $exe -ArgumentList '--smoke-test' -PassThru
if (-not $process.WaitForExit($TimeoutMilliseconds)) {
    $pid = $process.Id
    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    Write-RelevantApplicationEvents -Since $started -ProcessId $pid
    throw "MyMix smoke test did not exit within $TimeoutMilliseconds ms."
}

$exitCode = $process.ExitCode
if ($exitCode -ne 0) {
    Write-RelevantApplicationEvents -Since $started -ProcessId $process.Id
    throw "MyMix smoke test exited with code $exitCode (0x$([Convert]::ToString(($exitCode -band 0xffffffff), 16)))."
}

Write-Host 'MyMix startup smoke test passed.'
