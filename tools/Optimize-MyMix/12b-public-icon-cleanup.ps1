# Remove inherited application-icon resources by line, avoiding XML/regex formatting assumptions.
# Stage 13 then replaces runtime tray fallback behavior and asserts these resources are absent.
$appXamlPath = 'EarTrumpet/App.xaml'
$appXamlLines = Read-Text $appXamlPath -split '\r?\n'
$appXamlLines = @($appXamlLines | Where-Object { $_ -notmatch 'EarTrumpetIcon(?:Light|Dark)' })
Write-Text $appXamlPath (($appXamlLines -join "`r`n").TrimEnd() + "`r`n")

Assert-NotContains $appXamlPath 'EarTrumpetIconLight'
Assert-NotContains $appXamlPath 'EarTrumpetIconDark'
