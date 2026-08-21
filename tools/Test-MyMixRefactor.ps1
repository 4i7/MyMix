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

# Product identity / stripped runtime surface.
Assert-Contains 'EarTrumpet/MyMix.csproj' '<AssemblyName>MyMix</AssemblyName>'
Assert-Contains 'MyMix.sln' '= "MyMix", "EarTrumpet\MyMix.csproj"'
Assert-Contains 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs' '@"Software\MyMix"'
foreach ($file in @('EarTrumpet/App.config','EarTrumpet/packages.config','EarTrumpet/MyMix.csproj','EarTrumpet/Diagnosis/ErrorReporter.cs')) { Assert-NotContains $file 'Bugsnag' }
foreach ($path in @('EarTrumpet/Assets/Icon-Light.ico','EarTrumpet/Assets/Icon-Dark.ico','EarTrumpet/Assets/Welcome.gif','EarTrumpet/Assets/Logo-Dark.png','EarTrumpet/Assets/Logo-Light.png','EarTrumpet/Addons','EarTrumpet/Extensibility','EarTrumpet.ColorTool','EarTrumpet.Package','.chocolatey')) { Assert-PathMissing $path }
Assert-NotContains 'EarTrumpet/App.xaml.cs' 'RenderMode.SoftwareOnly'
Assert-Contains 'EarTrumpet/App.xaml.cs' '--smoke-test'
Assert-Contains 'EarTrumpet/App.xaml.cs' 'DispatcherPriority.ApplicationIdle'

# Mixer UI / peak path: visible-only 30 FPS, no backlog, no audio-path queueing.
$peaks = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
Assert-Contains $peaks 'new Timer(1000.0 / 30.0)'
Assert-Contains $peaks 'DispatcherPriority.Render'
Assert-Contains $peaks 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
Assert-Contains $peaks 'ShouldSampleAllPeakDevices'
Assert-Contains $peaks '_deviceManager.UpdatePeakValues();'
Assert-Contains $peaks '_deviceManager.UpdatePeakValues(Default.Id)'
Assert-Contains $peaks 'TemporaryAppItemViewModel tempApp = null;'
Assert-Contains $peaks 'tempApp?.Dispose();'
Assert-Contains $peaks 'public void ToggleDefaultMute()'
Assert-Contains $peaks 'public void CycleDefaultDevice()'
Assert-NotMatches $peaks '(?ms)private void UpdatePeakValuesForVisibleSurfaces\(\)\s*\{\s*if \(ShouldSampleAllPeakDevices\)\s*\{\s*UpdatePeakValuesForVisibleSurfaces\(\);'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' '_deviceVolume.SetMasterVolumeLevelScalar(rawVolume, ref dummy);'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' '_simpleVolume.SetMasterVolume(rawVolume, ref dummy);'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'QueueVolumeUiUpdate();'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'QueueVolumeUiUpdate();'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'meter.GetPeakValue()'
Assert-NotContains 'EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs' 'AllocHGlobal'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'PeakReleaseFactor = 0.72f'
foreach ($path in @('EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs','EarTrumpet/UI/Controls/VolumeSlider.cs','EarTrumpet/UI/Views/AppItemView.xaml','EarTrumpet/UI/Views/DeviceView.xaml','EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs')) { Assert-NotContains $path 'PeakValue2' }

# Settings are cached in memory; hotkeys are WM_HOTKEY based and execute only on user input.
Assert-Contains 'EarTrumpet/AppSettings.cs' 'Runtime reads are memory-only'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'ToggleMuteHotkeyTyped'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'CycleOutputDeviceHotkeyTyped'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'public int VolumeStep'
Assert-Contains 'EarTrumpet/Interop/Helpers/HotkeyManager.cs' 'User32.RegisterHotKey'
Assert-Contains 'EarTrumpet/Interop/Helpers/HotkeyManager.cs' 'User32.WM_HOTKEY'
Assert-Contains 'EarTrumpet/App.xaml.cs' 'Settings.ToggleMuteHotkeyTyped += CollectionViewModel.ToggleDefaultMute;'
Assert-Contains 'EarTrumpet/App.xaml.cs' 'Settings.CycleOutputDeviceHotkeyTyped += CollectionViewModel.CycleDefaultDevice;'
Assert-Contains 'EarTrumpet/App.xaml.cs' 'Math.Sign(wheelDelta) * Settings.VolumeStep'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public void IncrementVolume(int delta) => Volume += delta;'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'get => _stream.Volume.ToVolumeInt();'
Assert-Contains 'EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs' 'set => _stream.Volume = value / 100f;'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs' 'var rawVolume = displayVolume.ToLogVolume();'
Assert-Contains 'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs' 'var rawVolume = displayVolume.ToLogVolume();'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' 'private const double CurveFactor = 3.5;'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' 'Math.Exp(CurveFactor * val) * InverseCurveScale'
Assert-Contains 'EarTrumpet/Extensions/FloatExtensions.cs' '(Math.Log(val) + CurveFactor) / CurveFactor'
Assert-Contains 'EarTrumpet/Properties/Resources.resx' '<value>Volume step</value>'
Assert-Contains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'ChangePositionByAmount(Math.Sign(e.Delta) * (EarTrumpet.App.Settings?.VolumeStep ?? 2));'
Assert-NotContains 'EarTrumpet/UI/Controls/VolumeSlider.cs' 'ChangePositionByAmount(Math.Sign(e.Delta) * 2.0);'
Assert-Contains 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' '?? "Volume step";'
Assert-NotContains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Text="1%"'
Assert-NotContains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Text="10%"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Content="{Binding ToggleMuteHotkey}"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Content="{Binding CycleOutputDeviceHotkey}"'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'if (value < 1) return 1;'
Assert-Contains 'EarTrumpet/AppSettings.cs' 'if (value > 10) return 10;'
Assert-Contains 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' 'public double VolumeStep'
Assert-Contains 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' 'VolumeStepDisplayText'
Assert-NotContains 'EarTrumpet/UI/ViewModels/EarTrumpetMouseSettingsPageViewModel.cs' 'VolumeStepOptions'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' '<Slider Width="280"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Minimum="1"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Maximum="10"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'TickFrequency="1"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'IsSnapToTickEnabled="True"'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'Value="{Binding VolumeStep, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"'
Assert-NotContains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'ItemsSource="{Binding VolumeStepOptions}"'

# Windows sign-in startup is explicitly opt-in. Launching MyMix must never register it by itself.
Assert-Contains 'EarTrumpet/App.xaml.cs' "private static bool IsStartupRegistrationEnabled()"
Assert-Contains 'EarTrumpet/App.xaml.cs' "private static void SetStartupRegistration(bool enabled)"
Assert-Contains 'EarTrumpet/App.xaml.cs' "Software\Microsoft\Windows\CurrentVersion\Run"
Assert-Contains 'EarTrumpet/App.xaml.cs' "Command = new RelayCommand(ToggleStartupRegistration)"
Assert-Contains 'EarTrumpet/App.xaml.cs' "Start MyMix at Windows sign-in"
Assert-NotContains 'EarTrumpet/App.xaml.cs' "EnsureStartupRegistration()"

# Process lifetime tracking is generation-aware, event-driven and never publishes an unresolved watcher candidate.
$watcher = 'EarTrumpet/DataModel/ProcessWatcherService.cs'
foreach ($needle in @(
    'public static IDisposable WatchProcess',
    'internal static ProcessWatchLease TryWatchProcess',
    'ProcessWatchStatus',
    'ProcessGenerationState',
    'private ProcessWatchLease(',
    'public bool IsPublished;',
    'public bool ExitObserved;',
    'public bool Completed;',
    's_getProcessById',
    's_enableRaisingEvents',
    'GetUnpublishedCandidateState',
    'GetPublishedGenerationState',
    'ReferenceEquals(current, winner)',
    'UnwatchProcess(ProcessWatcherData expected',
    'ProcessWatcherService callback failed')) { Assert-Contains $watcher $needle }
foreach ($forbidden in @('PollIntervalMilliseconds','Thread.Sleep(','WaitForSingleObject(','WaitForMultipleObjects(','s_threadRunning','new Thread(WatcherLoop)','UnwatchProcess(int processId')) { Assert-NotContains $watcher $forbidden }

# Event delivery may happen during construction, so both legacy metadata classes and the cached Entry keep sticky one-shot stop semantics.
foreach ($appInfo in @('EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs','EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs')) {
    Assert-Contains $appInfo 'private readonly object _stoppedLock = new object();'
    Assert-Contains $appInfo 'private bool _isStopped;'
    Assert-Contains $appInfo 'if (_isStopped) invokeNow = true;'
    Assert-Contains $appInfo 'NotifyStopped()'
}
$factory = 'EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs'
foreach ($needle in @(
    'ConcurrentDictionary<int, Lazy<ProcessAppInfoEntry>>',
    'LazyThreadSafetyMode.ExecutionAndPublication',
    'ICollection<KeyValuePair<int, Lazy<ProcessAppInfoEntry>>>',
    'ReferenceEquals(actualLazy, candidateLazy)',
    'ProcessWatcherService.TryWatchProcess',
    'CreateCore(processId, false)',
    'EntryValidationState',
    'private sealed class ProcessAppInfoEntry : IAppInfo')) { Assert-Contains $factory $needle }
Assert-NotContains $factory 'ConcurrentDictionary<int, Lazy<IAppInfo>>'
Assert-NotContains $factory 'PublicationOnly'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' '_processWatchRegistrations'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' 'ProcessWatcherService.WatchProcess(pid, OnProcessQuit)'
Assert-Contains 'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs' 'Interlocked.Exchange(ref _disposed, 1)'
Assert-Contains 'EarTrumpet/UI/ViewModels/DeviceViewModel.cs' 'public override void Dispose()'

# Optimizer metadata and future upstream refresh must preserve the architecture and release identity.
foreach ($marker in @('version=5','peak_meter=30fps-visible-aggregate-smoothed-single-binding','vm_lifetime=explicit-dispose','icon_cache=bounded-frozen','appinfo_cache=per-process','audio_callbacks=coalesced','process_watcher=event-driven-process-exit-disposable-registrations','control_shortcuts=mute-cycle-output-configurable-step','volume_control=logarithmic-3.5-display-step','volume_step=shared-tray-and-slider','startup=opt-in-hkcu-run')) { Assert-Contains '.mymix-optimized' $marker }
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/15-lightweight-controls.ps1'"
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/17-startup-option.ps1'"
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/19-display-volume-curve.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/19-display-volume-curve.ps1'
Assert-Contains 'tools/Optimize-MyMix.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/20-shared-volume-step.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/20-shared-volume-step.ps1'
Assert-Contains 'tools/Optimize-MyMix/15-lightweight-controls.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/15-lightweight-controls-final.ps1'"
Assert-Contains 'tools/Optimize-MyMix/15-lightweight-controls.ps1' "Resolve-RepoPath 'tools/Optimize-MyMix/15-process-watcher-lifecycle.ps1'"
Assert-PathExists 'tools/Optimize-MyMix/15-process-watcher-lifecycle.ps1'
Assert-PathExists 'tools/Optimize-MyMix/16-appinfo-exit-race.ps1'
Assert-PathExists 'tools/Optimize-MyMix/17-startup-option.ps1'
Assert-Contains 'tools/Optimize-MyMix/10-appinfo-cache.ps1' 'ConcurrentDictionary<int, Lazy<ProcessAppInfoEntry>>'
Assert-Contains 'tools/Optimize-MyMix/15-process-watcher-lifecycle.ps1' 'GetUnpublishedCandidateState'
Assert-Contains 'tools/Optimize-MyMix/15-process-watcher-lifecycle.ps1' 'ReferenceEquals(current, winner)'
Assert-Contains 'tools/Update-FromEarTrumpet.ps1' 'Restore-MyMixReleaseMetadata'
Assert-Contains 'tools/Update-FromEarTrumpet.ps1' '-Force -SkipBuild -SkipValidation'
Assert-Contains 'tools/Convert-ToMyMix.ps1' '[switch]$SkipValidation'
Assert-Contains 'tools/Test-ProcessWatcherLifetime.ps1' 'Event-driven ProcessWatcherService registration/lifetime/race/stress validation passed.'
Assert-PathExists 'tools/Test-AppInfoCacheLifetime.ps1'
Assert-Contains 'tools/Test-AppInfoCacheLifetime.ps1' 'AppInfo cache/process-generation lifecycle validation passed.'
Assert-Contains 'tools/Test-AppInfoCacheLifetime.ps1' 'Test I - an unpublished candidate must not be visible/shared'
Assert-Contains 'tools/Test-AppInfoCacheLifetime.ps1' 'Test K - an exited candidate generation cannot transfer its callback'

# Distribution workflows remain explicit, reproducible and validate both watcher and AppInfo cache lifecycle paths.
$workflows = @('.github/workflows/apply-mymix.yml','.github/workflows/update-from-eartrumpet.yml','.github/workflows/release.yml','.github/workflows/validate-mymix.yml')
foreach ($workflow in $workflows) {
    Assert-NotContains $workflow 'actions/upload-artifact'
    Assert-NotContains $workflow 'actions/cache'
    Assert-Contains $workflow 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
    Assert-Contains $workflow 'NuGet/setup-nuget@fd55a6f3b34392fa83fde1454582407d8c714123'
    Assert-Contains $workflow 'microsoft/setup-msbuild@30375c66a4eea26614e0d39710365f22f8b0af57'
    Assert-Contains $workflow '.\tools\Test-ProcessWatcherLifetime.ps1'
    Assert-Contains $workflow '.\tools\Test-AppInfoCacheLifetime.ps1'
    Assert-Contains $workflow '.\tools\Smoke-TestMyMix.ps1'
}
Assert-Contains '.github/workflows/update-from-eartrumpet.yml' 'Verify regeneration matches committed MyMix source'
Assert-Contains '.github/workflows/update-from-eartrumpet.yml' 'Regenerated MyMix differs from committed source.'
Assert-Contains '.github/workflows/update-from-eartrumpet.yml' 'tools/Test-AppInfoCacheLifetime.ps1'
Assert-NotContains '.github/workflows/update-from-eartrumpet.yml' 'git push origin HEAD:main'
Assert-Contains '.github/workflows/validate-mymix.yml' 'pull_request:'
Assert-Contains '.github/workflows/validate-mymix.yml' 'push:'
Assert-PathMissing '.github/workflows/publish-v1.0.1.yml'
Assert-PathMissing '.github/workflows/publish-v1.0.2.yml'
Assert-PathMissing '.github/workflows/validate-lightweight-controls.yml'
Assert-Contains '.github/workflows/release.yml' 'name: Release MyMix'
Assert-Contains '.github/workflows/release.yml' 'workflow_dispatch:'
Assert-Contains '.github/workflows/release.yml' 'release.upload_url'
Assert-Contains '.github/workflows/release.yml' 'MyMix-x86.zip'
Assert-Contains '.github/workflows/release.yml' 'SHA256SUMS.txt'
Assert-Contains '.github/workflows/release.yml' 'Required release assets are missing; draft will not be published.'
Assert-NotContains '.github/workflows/release.yml' 'MyMix.pdb'

# Public documentation / privacy / license provenance.
foreach ($doc in @('README.md','PRIVACY.md','COMPILING.md','CONTRIBUTING.md','SECURITY.md','THIRD_PARTY_NOTICES.md','LICENSE','UPSTREAM_README.md')) { Assert-PathExists $doc }
Assert-Contains 'README.md' 'not an official EarTrumpet release'
Assert-Contains 'README.md' 'retains the upstream [LICENSE](LICENSE) verbatim'
Assert-Contains 'PRIVACY.md' 'does not automatically submit telemetry'
Assert-Contains 'THIRD_PARTY_NOTICES.md' 'explicit excluded entities'

if ($Failures.Count -gt 0) {
    Write-Host 'MyMix refactor validation failed:' -ForegroundColor Red
    foreach ($failure in $Failures) { Write-Host " - $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'MyMix refactor/lightweight-runtime/deterministic-regeneration/public-release validation passed.' -ForegroundColor Green
