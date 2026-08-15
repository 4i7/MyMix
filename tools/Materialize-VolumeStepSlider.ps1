#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)

Push-Location $repoRoot
try {
    .\tools\Optimize-MyMix\18-settings-ui-fix.ps1

    $old = @'
Assert-Contains 'EarTrumpet/UI/Views/SettingsWindow.xaml' 'ItemsSource="{Binding VolumeStepOptions}"'
'@.Trim()

    $new = @'
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
'@.Trim()

    foreach ($relativePath in @('tools/Optimize-MyMix.ps1', 'tools/Test-MyMixRefactor.ps1')) {
        $path = Join-Path $repoRoot $relativePath
        $text = [IO.File]::ReadAllText($path)
        if (-not $text.Contains($old)) { throw "Legacy volume-step invariant was not found in $relativePath" }
        $text = $text.Replace($old, $new)
        [IO.File]::WriteAllText($path, $text, $utf8)
    }

    [xml]([IO.File]::ReadAllText((Join-Path $repoRoot 'EarTrumpet/UI/Views/SettingsWindow.xaml'))) | Out-Null
    .\tools\Test-MyMixRefactor.ps1
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
