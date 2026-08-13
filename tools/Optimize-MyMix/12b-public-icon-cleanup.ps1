# Remove inherited application-icon resource declarations/references without touching any
# surrounding XAML structure. An empty theme DataTrigger is harmless; deleting its individual
# icon setter line is safer than a multiline regex that could consume unrelated XAML.
$appXamlPath = 'EarTrumpet/App.xaml'
$appXamlLines = (Read-Text $appXamlPath) -split '\r?\n'
$appXamlLines = @($appXamlLines | Where-Object { $_ -notmatch 'EarTrumpetIcon(?:Light|Dark)' })
$appXaml = (($appXamlLines -join "`r`n").TrimEnd() + "`r`n")
Write-Text $appXamlPath $appXaml

# FlyoutWindow also directly referenced the upstream application icon. Removing only the
# resource declaration compiles but fails at runtime with StaticResource/XamlParseException,
# so remove the reference and brand the window as MyMix in the same fail-fast stage.
$flyoutPath = 'EarTrumpet/UI/Views/FlyoutWindow.xaml'
$flyoutLines = (Read-Text $flyoutPath) -split '\r?\n'
$flyoutLines = @($flyoutLines | Where-Object { $_ -notmatch 'EarTrumpetIcon(?:Light|Dark)' })
$flyout = (($flyoutLines -join "`r`n").TrimEnd() + "`r`n")
$flyout = $flyout.Replace('Title="EarTrumpet"', 'Title="MyMix"')
Write-Text $flyoutPath $flyout

Assert-Contains $appXamlPath '<Application x:Class="EarTrumpet.App"'
Assert-Contains $appXamlPath '<Application.Resources>'
Assert-Contains $appXamlPath '</Application>'
Assert-NotContains $appXamlPath 'EarTrumpetIconLight'
Assert-NotContains $appXamlPath 'EarTrumpetIconDark'
Assert-NotContains $flyoutPath 'EarTrumpetIconLight'
Assert-NotContains $flyoutPath 'EarTrumpetIconDark'
Assert-Contains $flyoutPath 'Title="MyMix"'
