# Remove inherited application-icon resources and their style references without rewriting
# unrelated XAML. Stage 13 repeats the same cleanup defensively and owns the runtime fallback.
$appXamlPath = 'EarTrumpet/App.xaml'
$appXaml = Read-Text $appXamlPath
$appXaml = [regex]::Replace($appXaml, '(?m)^\s*<bcl:String\s+x:Key="EarTrumpetIcon(?:Light|Dark)">[^<]*</bcl:String>\r?\n?', '')
$appXaml = [regex]::Replace($appXaml, '(?m)^\s*<Setter\s+Property="Icon"\s+Value="\{Binding Source=\{StaticResource EarTrumpetIconLight\}\}"\s*/>\r?\n?', '')
$appXaml = [regex]::Replace($appXaml, '(?ms)^\s*<DataTrigger\s+Binding="\{Binding Source=\{StaticResource ThemeManager\}, Path=IsSystemLightTheme\}"\s+Value="False">\s*<Setter\s+Property="Icon"\s+Value="\{Binding Source=\{StaticResource EarTrumpetIconDark\}\}"\s*/>\s*</DataTrigger>\r?\n?', '')
Write-Text $appXamlPath $appXaml

Assert-NotContains $appXamlPath 'EarTrumpetIconLight'
Assert-NotContains $appXamlPath 'EarTrumpetIconDark'
