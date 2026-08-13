#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$UpstreamRepository = 'https://github.com/File-New-Project/EarTrumpet.git',
    [string]$UpstreamRef = 'master',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Marker = Join-Path $Root '.mymix-converted'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$UpstreamWorktree = Join-Path $TempBase ('mymix-eartrumpet-' + [Guid]::NewGuid().ToString('N'))

function Write-WorkflowOutput([string]$Name, [string]$Value) {
    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
    Write-Host "$Name=$Value"
}

function Invoke-Git([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }
}

function Invoke-GitCapture([string[]]$Arguments) {
    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }
    return ($output -join "`n").Trim()
}

function Get-CurrentUpstreamSha {
    if (-not (Test-Path -LiteralPath $Marker)) {
        return $null
    }

    $text = [IO.File]::ReadAllText($Marker)
    $match = [regex]::Match($text, '(?m)^upstream=File-New-Project/EarTrumpet@([0-9a-fA-F]{40})\s*$')
    if ($match.Success) {
        return $match.Groups[1].Value.ToLowerInvariant()
    }

    return $null
}

function Copy-UpstreamIntoRepository {
    $preserve = @('.git', '.github', 'tools')

    Get-ChildItem -LiteralPath $Root -Force | Where-Object {
        $_.Name -notin $preserve
    } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }

    $upstreamReadme = Join-Path $UpstreamWorktree 'README.md'
    if (Test-Path -LiteralPath $upstreamReadme) {
        Copy-Item -LiteralPath $upstreamReadme -Destination (Join-Path $Root 'UPSTREAM_README.md') -Force
    }

    foreach ($item in Get-ChildItem -LiteralPath $UpstreamWorktree -Force) {
        if ($item.Name -in @('.git', '.github', 'README.md')) {
            continue
        }

        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Root $item.Name) -Recurse -Force
    }
}

try {
    New-Item -ItemType Directory -Path $UpstreamWorktree -Force | Out-Null
    Invoke-Git @('-C', $UpstreamWorktree, 'init', '--quiet')
    Invoke-Git @('-C', $UpstreamWorktree, 'remote', 'add', 'origin', $UpstreamRepository)
    Invoke-Git @('-C', $UpstreamWorktree, 'fetch', '--depth', '1', 'origin', $UpstreamRef)
    Invoke-Git @('-C', $UpstreamWorktree, 'checkout', '--quiet', '--detach', 'FETCH_HEAD')

    $upstreamSha = Invoke-GitCapture @('-C', $UpstreamWorktree, 'rev-parse', 'HEAD')
    $upstreamSha = $upstreamSha.ToLowerInvariant()
    $upstreamShort = $upstreamSha.Substring(0, 12)
    $currentSha = Get-CurrentUpstreamSha

    Write-Host "Current MyMix upstream: $currentSha"
    Write-Host "Requested EarTrumpet upstream: $upstreamSha ($UpstreamRef)"

    Write-WorkflowOutput 'upstream_sha' $upstreamSha
    Write-WorkflowOutput 'upstream_short' $upstreamShort
    Write-WorkflowOutput 'upstream_ref' $UpstreamRef

    if (-not $Force -and $currentSha -eq $upstreamSha) {
        Write-Host 'MyMix already contains this EarTrumpet upstream commit.'
        Write-WorkflowOutput 'changed' 'false'
        exit 0
    }

    Copy-UpstreamIntoRepository

    $converter = Join-Path $PSScriptRoot 'Convert-ToMyMix.ps1'
    & $converter -Force -SkipBuild

    $finalizer = Join-Path $PSScriptRoot 'Finalize-StandaloneMyMix.ps1'
    & $finalizer

    $markerText = @(
        "upstream=File-New-Project/EarTrumpet@$upstreamSha"
        "upstream_ref=$UpstreamRef"
        "converted=$(Get-Date -Format o)"
    ) -join "`n"
    [IO.File]::WriteAllText($Marker, $markerText + "`n", $Utf8NoBom)

    $validator = Join-Path $PSScriptRoot 'Test-MyMixRefactor.ps1'
    & $validator

    Write-WorkflowOutput 'changed' 'true'
    Write-Host "EarTrumpet $upstreamSha was converted to MyMix successfully."
}
finally {
    Remove-Item -LiteralPath $UpstreamWorktree -Recurse -Force -ErrorAction SilentlyContinue
}
