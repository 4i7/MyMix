# -----------------------------------------------------------------------------
# 7. Project/output trimming: release tracing/PDBs, add-ons, per-channel controls,
#    unused packages/references, tools/packages not part of standalone MyMix, and
#    non-Japanese satellite resources. Neutral English resources remain fallback.
# -----------------------------------------------------------------------------
$projectPath = 'EarTrumpet/MyMix.csproj'
$project = Read-Text $projectPath
$project = $project.Replace('<DefineConstants>TRACE;X86</DefineConstants>', '<DefineConstants>X86</DefineConstants>')
$project = $project.Replace('<DebugType>pdbonly</DebugType>', '<DebugType>none</DebugType>')

foreach ($reference in @('Newtonsoft.Json', 'XamlAnimatedGif')) {
    $pattern = '(?ms)^\s*<Reference Include="' + [regex]::Escape($reference) + ',.*?</Reference>\r?\n'
    $project = [regex]::Replace($project, $pattern, '')
}
foreach ($reference in @('System.ComponentModel.Composition', 'System.Configuration', 'System.Management', 'System.Net.Http', 'Microsoft.CSharp')) {
    $pattern = '(?m)^\s*<Reference Include="' + [regex]::Escape($reference) + '" />\r?\n'
    $project = [regex]::Replace($project, $pattern, '')
}
foreach ($prefix in @('Addons\', 'Extensibility\')) {
    $pattern = '(?m)^\s*<Compile Include="' + [regex]::Escape($prefix) + '[^"]+" />\r?\n'
    $project = [regex]::Replace($project, $pattern, '')
}
foreach ($include in @(
    'Extensions\EarTrumpetAddonExtensions.cs',
    'DebugHelpers.cs',
    'DataModel\Audio\Mocks\AudioDevice.cs',
    'DataModel\Audio\Mocks\AudioDeviceSession.cs',
    'DataModel\FilteredCollectionChain.cs',
    'DataModel\WindowsAudio\IAudioDeviceChannel.cs',
    'DataModel\WindowsAudio\IAudioDeviceSessionChannel.cs',
    'DataModel\WindowsAudio\Internal\AudioDeviceChannel.cs',
    'DataModel\WindowsAudio\Internal\AudioDeviceChannelCollection.cs',
    'DataModel\WindowsAudio\Internal\AudioDeviceSessionChannel.cs',
    'DataModel\WindowsAudio\Internal\AudioDeviceSessionChannelCollection.cs',
    'DataModel\WindowsAudio\Internal\AudioDeviceSessionChannelMultiplexer.cs',
    'Interop\MMDeviceAPI\IChannelAudioVolume.cs',
    'Interop\MMDeviceAPI\IDeviceTopology.cs',
    'Diagnosis\CircularBufferTraceListener.cs',
    'UI\ViewModels\AddonAboutPageViewModel.cs',
    'UI\ViewModels\AdvertisedCategorySettingsViewModel.cs',
    'UI\ViewModels\EarTrumpetCommunitySettingsPageViewModel.cs',
    'UI\ViewModels\EarTrumpetLegacySettingsPageViewModel.cs',
    'UI\ViewModels\WelcomeViewModel.cs',
    'Features.cs'
)) {
    $escaped = [regex]::Escape($include)
    $pattern = '(?m)^\s*<Compile Include="' + $escaped + '" />\r?\n'
    $project = [regex]::Replace($project, $pattern, '')
}
$project = [regex]::Replace($project, '(?ms)^\s*<Page Include="Addons\\EarTrumpet\.Actions\\AddonResources\.xaml">.*?</Page>\r?\n', '')
$project = [regex]::Replace($project, '(?m)^\s*<Resource Include="Assets\\Welcome\.gif" />\r?\n', '')
$project = [regex]::Replace($project, '(?m)^\s*<None Include="prebuild\.ps1" />\r?\n', '')
$project = [regex]::Replace($project, '(?m)^\s*<EmbeddedResource Include="Properties\\Resources\.(?!ja-JP\.resx)[^"]+\.resx" />\r?\n', '')
Write-Text $projectPath $project

Write-Text 'EarTrumpet/App.config' @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <startup>
        <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.6.2" />
    </startup>
    <runtime>
        <AppContextSwitchOverrides value="Switch.System.Windows.DoNotScaleForDpiChanges=false" />
    </runtime>
</configuration>
'@

$packagesPath = 'EarTrumpet/packages.config'
$packages = Read-Text $packagesPath
$packages = [regex]::Replace($packages, '(?m)^\s*<package id="Newtonsoft\.Json"[^>]*/>\r?\n', '')
$packages = [regex]::Replace($packages, '(?m)^\s*<package id="XamlAnimatedGif"[^>]*/>\r?\n', '')
Write-Text $packagesPath $packages

foreach ($resource in Get-ChildItem -LiteralPath (Resolve-RepoPath 'EarTrumpet/Properties') -Filter 'Resources.*.resx' -File) {
    if ($resource.Name -ne 'Resources.ja-JP.resx') {
        Remove-Item -LiteralPath $resource.FullName -Force
    }
}

foreach ($path in @(
    '.chocolatey',
    'EarTrumpet.ColorTool',
    'EarTrumpet.Package',
    'EarTrumpet/Addons',
    'EarTrumpet/Extensibility',
    'EarTrumpet/DataModel/Audio/Mocks',
    'EarTrumpet/DataModel/FilteredCollectionChain.cs',
    'EarTrumpet/DataModel/WindowsAudio/IAudioDeviceChannel.cs',
    'EarTrumpet/DataModel/WindowsAudio/IAudioDeviceSessionChannel.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceChannel.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceChannelCollection.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionChannel.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionChannelCollection.cs',
    'EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSessionChannelMultiplexer.cs',
    'EarTrumpet/Interop/MMDeviceAPI/IChannelAudioVolume.cs',
    'EarTrumpet/Interop/MMDeviceAPI/IDeviceTopology.cs',
    'EarTrumpet/Extensions/EarTrumpetAddonExtensions.cs',
    'EarTrumpet/DebugHelpers.cs',
    'EarTrumpet/Diagnosis/CircularBufferTraceListener.cs',
    'EarTrumpet/UI/ViewModels/AddonAboutPageViewModel.cs',
    'EarTrumpet/UI/ViewModels/AdvertisedCategorySettingsViewModel.cs',
    'EarTrumpet/UI/ViewModels/EarTrumpetCommunitySettingsPageViewModel.cs',
    'EarTrumpet/UI/ViewModels/EarTrumpetLegacySettingsPageViewModel.cs',
    'EarTrumpet/UI/ViewModels/WelcomeViewModel.cs',
    'EarTrumpet/Features.cs',
    'EarTrumpet/Assets/Welcome.gif',
    'EarTrumpet/prebuild.ps1',
    'GitVersion.yml'
)) {
    Remove-Path $path
}

Write-Text 'MyMix.sln' @'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 16
VisualStudioVersion = 16.0.29306.81
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyMix", "EarTrumpet\MyMix.csproj", "{BA3C7B42-84B0-468C-8640-217E2A24CF81}"
EndProject
Global
    GlobalSection(SolutionConfigurationPlatforms) = preSolution
        Debug|x86 = Debug|x86
        Release|x86 = Release|x86
        VSDebug|x86 = VSDebug|x86
    EndGlobalSection
    GlobalSection(ProjectConfigurationPlatforms) = postSolution
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.Debug|x86.ActiveCfg = Debug|x86
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.Debug|x86.Build.0 = Debug|x86
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.Release|x86.ActiveCfg = Release|x86
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.Release|x86.Build.0 = Release|x86
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.VSDebug|x86.ActiveCfg = VSDebug|x86
        {BA3C7B42-84B0-468C-8640-217E2A24CF81}.VSDebug|x86.Build.0 = VSDebug|x86
    EndGlobalSection
    GlobalSection(SolutionProperties) = preSolution
        HideSolutionNode = FALSE
    EndGlobalSection
EndGlobal
'@
