#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function RepoPath([string]$RelativePath) { Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar) }
function ReadRepo([string]$RelativePath) {
    $path = RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { $Failures.Add("Missing: $RelativePath"); return '' }
    [IO.File]::ReadAllText($path)
}
function Assert-Contains([string]$Path, [string]$Needle) { if (-not (ReadRepo $Path).Contains($Needle)) { $Failures.Add("$Path missing: $Needle") } }
function Assert-NotContains([string]$Path, [string]$Needle) { if ((ReadRepo $Path).Contains($Needle)) { $Failures.Add("$Path still contains: $Needle") } }
function Assert-NotMatches([string]$Path, [string]$Pattern) { if ((ReadRepo $Path) -match $Pattern) { $Failures.Add("$Path matches forbidden pattern: $Pattern") } }
function Assert-PathMissing([string]$Path) { if (Test-Path -LiteralPath (RepoPath $Path)) { $Failures.Add("Path should be removed: $Path") } }
function Assert-PathExists([string]$Path) { if (-not (Test-Path -LiteralPath (RepoPath $Path))) { $Failures.Add("Required path missing: $Path") } }

Assert-Contains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Margin="0,0,16,0"'
Assert-Contains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Margin="0,0,16,0"'
Assert-NotContains 'EarTrumpet/UI/Views/AppItemView.xaml' 'Grid.Column="2" Text="{Binding Volume'
Assert-NotContains 'EarTrumpet/UI/Views/DeviceView.xaml' 'Grid.Column="2"'
Assert-NotContains 'EarTrumpet/UI/Mutable.xaml' 'Mutable_VolumeCellWidth'
foreach ($file in @('EarTrumpet/App.config', 'EarTrumpet/packages.config', 'EarTrumpet/MyMix.csproj', 'EarTrumpet/Diagnosis/ErrorReporter.cs')) { Assert-NotContains $file 'Bugsnag' }
Assert-Contains 'EarTrumpet/MyMix.csproj' '<AssemblyName>MyMix</AssemblyName>'
Assert-Contains 'MyMix.sln' '= "MyMix", "EarTrumpet\MyMix.csproj"'
Assert-Contains 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' '@"Software\MyMix"'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'OpenFeedbackCommand'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'File-New-Project/EarTrumpet/issues'

$Optimized = Test-Path -LiteralPath (RepoPath '.mymix-optimized')
if ($Optimized) {
    foreach ($doc in @('README.md', 'PRIVACY.md', 'COMPILING.md', 'CONTRIBUTING.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE', 'UPSTREAM_README.md')) { Assert-PathExists $doc }
    Assert-Contains 'README.md' 'not an official EarTrumpet release'
    Assert-Contains 'README.md' 'retains the upstream [LICENSE](LICENSE) verbatim'
    Assert-Contains 'PRIVACY.md' 'does not automatically submit telemetry'
    Assert-Contains 'THIRD_PARTY_NOTICES.md' 'explicit excluded entities'
    Assert-Contains 'tools/Update-FromEarTrumpet.ps1' '$MyMixDocs'
    Assert-Contains 'tools/Update-FromEarTrumpet.ps1' 'local LICENSE does not exactly match the imported EarTrumpet LICENSE'

    foreach ($name in @('UseLegacyIcon', 'IsTelemetryEnabled', 'UseLogarithmicVolume', 'HasShownFirstRun')) { Assert-NotContains 'EarTrumpet/AppSettings.cs' $name }

    $peaks = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
    Assert-Contains $peaks 'new Timer(1000.0 / 30.0)'
    Assert-Contains $peaks 'DispatcherPriority.Render'
    Assert-Contains $peaks 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
    Assert-Contains $peaks 'ShouldSampleAllPeakDevices'
    Assert-Contains $peaks '_deviceManager.UpdatePeakValues();'
    Assert-Contains $peaks '_deviceManager.UpdatePeakValues(Default.Id)'
    Assert-Contains $peaks 'foreach (var device in AllDevices)'
    Assert-NotMatches $peaks '(?ms)private void UpdatePeakValuesForVisibleSurfaces\(\)\s*\{\s*if \(ShouldSampleAllPeakDevices\)\s*\{\s*UpdatePeakValuesForVisibleSurfaces\(\);'
    Assert-NotMatches $peaks '(?ms)private void UpdatePeakForegroundForVisibleSurfaces\(\)\s*\{\s*if \(ShouldSampleAllPeakDevices\)\s*\{\s*UpdatePeakForegroundForVisibleSurfaces\(\);'
    Assert-NotMatches $peaks '(?m)for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);\s*\r?\n\s*for \(var i = 0; i < AllDevices\.Count; i\+\+\) AllDevices\[i\]\.Dispose\(\);'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'AllocHGlobal'
    Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'GetChannelsPeakValues'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
    foreach ($path in @('EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs','EarTrumpet/UI/Controls/VolumeSlider.cs','EarTrumpet/UI/Views/AppItemView.xaml','EarTrumpet/UI/Views/DeviceView.xaml','EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs')) { Assert-NotContains $path 'PeakValue2' }

    foreach ($marker in @('version=4','peak_meter=30fps-visible-aggregate-smoothed-single-binding','vm_lifetime=explicit-dispose','icon_cache=bounded-frozen','appinfo_cache=per-process','audio_callbacks=coalesced','public_hardening=unbranded-icons-safe-finalizer-smoke-test','process_watcher=scalable-single-thread-polling')) { Assert-Contains '.mymix-optimized' $marker }
    Assert-Contains 'EarTrumpet/MyMix.csproj' '<DefineConstants>X86</DefineConstants>'
    Assert-Contains 'EarTrumpet/MyMix.csproj' '<DebugType>none</DebugType>'
    foreach ($needle in @('Newtonsoft.Json','XamlAnimatedGif','System.ComponentModel.Composition','Addons\','Extensibility\','CircularBufferTraceListener.cs','FilteredCollectionChain.cs','AudioDeviceChannelCollection.cs','Logo-Dark.png','Logo-Light.png','Icon-Dark.ico','Icon-Light.ico')) { Assert-NotContains 'EarTrumpet/MyMix.csproj' $needle }
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'RenderMode.SoftwareOnly'
    Assert-NotContains 'EarTrumpet/App.xaml' 'WelcomeViewModel'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'public virtual void Dispose()'
    Assert-Contains 'EarTrumpet/UI/ViewModels/AppItemViewModel.cs' 'public override void Dispose()'
    Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public override void Dispose()'
    Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'ConcurrentDictionary<string, ImageSource>'
    Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'image.Freeze()'
    Assert-Contains 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs' 'ConcurrentDictionary<int, Lazy<IAppInfo>>'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'QueueVolumeUiUpdate();'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'QueueVolumeUiUpdate();'

    # Process lifetime stability: the generated source no longer calls the inherited multi-handle
    # wait API and background callback exceptions are contained.
    Assert-NotContains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'Kernel32.WaitForMultipleObjects('
    Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'PollIntervalMilliseconds = 500'
    Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'WaitForSingleObject(data.ProcessHandle, 0)'
    Assert-Contains 'EarTrumpet/DataModel/ProcessWatcherService.cs' 'ProcessWatcherService callback failed'

    foreach ($path in @('EarTrumpet/Assets/Icon-Light.ico','EarTrumpet/Assets/Icon-Dark.ico','EarTrumpet/Assets/Welcome.gif','EarTrumpet/Assets/Logo-Dark.png','EarTrumpet/Assets/Logo-Light.png','EarTrumpet/Addons','EarTrumpet/Extensibility','EarTrumpet.ColorTool','EarTrumpet.Package','.chocolatey')) { Assert-PathMissing $path }
    Assert-Contains 'EarTrumpet/App.xaml' '<Application x:Class="EarTrumpet.App"'
    Assert-Contains 'EarTrumpet/App.xaml' '<Application.Resources>'
    Assert-Contains 'EarTrumpet/App.xaml' '</Application>'
    Assert-NotContains 'EarTrumpet/App.xaml' 'EarTrumpetIconLight'
    Assert-NotContains 'EarTrumpet/App.xaml' 'EarTrumpetIconDark'
    Assert-Contains 'EarTrumpet/UI/Views/FlyoutWindow.xaml' '<Window x:Class="EarTrumpet.UI.Views.FlyoutWindow"'
    Assert-NotContains 'EarTrumpet/UI/Views/FlyoutWindow.xaml' 'EarTrumpetIconLight'
    Assert-NotContains 'EarTrumpet/UI/Views/FlyoutWindow.xaml' 'EarTrumpetIconDark'
    Assert-Contains 'EarTrumpet/UI/Views/FlyoutWindow.xaml' 'Title="MyMix"'
    Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'IconKind.EarTrumpet'
    Assert-Contains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'SystemIcons.Application.Clone()'
    Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetAboutPageViewModel.cs' 'intentional local diagnostic crash'
    Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionCollection.cs' '_sessionManager?.UnregisterSessionNotification(this);'
    Assert-Contains $peaks 'allExisting.Dispose();'
    Assert-Contains $peaks 'AllDevices[i].Dispose();'
    Assert-Contains 'EarTrumpet/Interop/Helpers/SingleInstanceAppMutex.cs' 'MYMIX_MUTEX_SUFFIX'
    Assert-Contains 'EarTrumpet/App.xaml.cs' '--smoke-test'
    Assert-Contains 'EarTrumpet/App.xaml.cs' 'DispatcherPriority.ApplicationIdle'
    Assert-Contains 'EarTrumpet/Diagnosis/LocalDataExporter.cs' 'MyMix-diagnostics-'
    Assert-NotContains 'EarTrumpet/Properties/Resources.resx' 'eartrumpet.app/jmp/fixfonts'

    $localized = @(Get-ChildItem -LiteralPath (RepoPath 'EarTrumpet/Properties') -Filter 'Resources.*.resx' -File | Select-Object -ExpandProperty Name)
    foreach ($name in $localized) { if ($name -ne 'Resources.ja-JP.resx') { $Failures.Add("Unexpected localized resource remains: $name") } }
}
else {
    Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => false;'
    Assert-Contains 'EarTrumpet/AppSettings.cs' 'get => true;'
    Assert-NotContains 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs' 'UseLegacyIcon'
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Load'
    Assert-NotContains 'EarTrumpet/App.xaml.cs' 'AddonManager.Host'
}

# All workflows must avoid Actions artifact/cache storage, use current Node 24 actions pinned by
# commit SHA, and share the same smoke-test implementation so diagnostics cannot drift.
$workflows = @('.github/workflows/apply-mymix.yml', '.github/workflows/update-from-eartrumpet.yml', '.github/workflows/release.yml')
foreach ($workflow in $workflows) {
    Assert-NotContains $workflow 'actions/upload-artifact'
    Assert-NotContains $workflow 'actions/cache'
    Assert-NotContains $workflow 'deleteArtifact'
    Assert-NotContains $workflow 'actions: write'
    Assert-Contains $workflow 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
    Assert-Contains $workflow 'NuGet/setup-nuget@fd55a6f3b34392fa83fde1454582407d8c714123'
    Assert-Contains $workflow 'microsoft/setup-msbuild@30375c66a4eea26614e0d39710365f22f8b0af57'
    Assert-Contains $workflow 'Smoke test MyMix startup'
    Assert-Contains $workflow '.\tools\Smoke-TestMyMix.ps1'
}

# Source-mutating workflows are serialized. Apply is manual-only; update is the one controlled
# main-push validator and must cover every workflow/shared script that can affect Actions.
Assert-Contains '.github/workflows/apply-mymix.yml' 'group: mymix-source-maintenance'
Assert-NotMatches '.github/workflows/apply-mymix.yml' '(?m)^\s*push\s*:'
Assert-Contains '.github/workflows/update-from-eartrumpet.yml' 'group: mymix-source-maintenance'
Assert-NotMatches '.github/workflows/update-from-eartrumpet.yml' '(?m)^\s*schedule\s*:'
foreach ($path in @('.github/workflows/apply-mymix.yml','.github/workflows/update-from-eartrumpet.yml','.github/workflows/release.yml','tools/Optimize-MyMix/**','tools/Test-MyMixRefactor.ps1','tools/Smoke-TestMyMix.ps1')) {
    Assert-Contains '.github/workflows/update-from-eartrumpet.yml' $path
}
Assert-Contains '.github/workflows/update-from-eartrumpet.yml' 'actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3'

# Release distribution is an explicit maintainer action only. It must use the upload_url returned
# by GitHub (uploads.github.com), publish only after both assets exist, include checksum/license/
# privacy/provenance, and never ship debug symbols.
Assert-Contains '.github/workflows/release.yml' 'name: Release MyMix'
Assert-NotMatches '.github/workflows/release.yml' '(?m)^\s*push\s*:'
Assert-Contains '.github/workflows/release.yml' 'workflow_dispatch:'
Assert-Contains '.github/workflows/release.yml' 'MyMix-x86.zip'
Assert-Contains '.github/workflows/release.yml' 'SHA256SUMS.txt'
Assert-Contains '.github/workflows/release.yml' "'LICENSE', 'README.md', 'PRIVACY.md', 'THIRD_PARTY_NOTICES.md'"
Assert-Contains '.github/workflows/release.yml' 'release.upload_url'
Assert-Contains '.github/workflows/release.yml' 'process.env.UPSTREAM_SHA'
Assert-Contains '.github/workflows/release.yml' 'draft: true'
Assert-Contains '.github/workflows/release.yml' 'draft: false'
Assert-Contains '.github/workflows/release.yml' 'Required release assets are missing; draft will not be published.'
Assert-NotContains '.github/workflows/release.yml' 'MyMix.pdb'
Assert-NotContains '.github/workflows/release.yml' 'upload-artifact'
Assert-Contains '.github/workflows/release.yml' 'actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3'

if ($Failures.Count -gt 0) {
    Write-Host 'MyMix refactor validation failed:' -ForegroundColor Red
    foreach ($failure in $Failures) { Write-Host " - $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'MyMix refactor/public-release validation passed.' -ForegroundColor Green
