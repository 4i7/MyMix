# Remove inherited application-icon resource declarations/references without touching any
# surrounding XAML structure. An empty theme DataTrigger is harmless; deleting its individual
# icon setter line is safer than a multiline regex that could consume unrelated XAML.
$appXamlPath = 'EarTrumpet/App.xaml'
$appXamlLines = (Read-Text $appXamlPath) -split '\r?\n'
$appXamlLines = @($appXamlLines | Where-Object { $_ -notmatch 'EarTrumpetIcon(?:Light|Dark)' })
$appXaml = (($appXamlLines -join "`r`n").TrimEnd() + "`r`n")
Write-Text $appXamlPath $appXaml

Assert-Contains $appXamlPath '<Application x:Class="EarTrumpet.App"'
Assert-Contains $appXamlPath '<Application.Resources>'
Assert-Contains $appXamlPath '</Application>'
Assert-NotContains $appXamlPath 'EarTrumpetIconLight'
Assert-NotContains $appXamlPath 'EarTrumpetIconDark'
