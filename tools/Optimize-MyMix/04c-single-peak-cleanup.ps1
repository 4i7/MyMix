# Remove residual second-peak assignments left by upstream view models after the
# aggregate peak path collapses both visual rails onto PeakValue1.
foreach ($path in @(
    'EarTrumpet/UI/ViewModels/TemporaryAppItemViewModel.cs',
    'EarTrumpet/UI/ViewModels/SettingsAppItemViewModel.cs'
)) {
    $text = Read-Text $path
    $text = [regex]::Replace($text, '(?m)^\s*PeakValue2\s*=.*;\r?\n', '')
    Write-Text $path $text
    Assert-NotContains $path 'PeakValue2'
}
