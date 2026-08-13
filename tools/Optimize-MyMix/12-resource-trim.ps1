# Final payload trim: these logo bitmaps were only used by removed welcome/packaging paths.
$projectPath = 'EarTrumpet/MyMix.csproj'
$project = Read-Text $projectPath
$project = [regex]::Replace($project, '(?m)^\s*<Resource Include="Assets\\Logo-(?:Dark|Light)\.png" />\r?\n', '')
Write-Text $projectPath $project
Remove-Path 'EarTrumpet/Assets/Logo-Dark.png'
Remove-Path 'EarTrumpet/Assets/Logo-Light.png'

Assert-NotContains $projectPath 'Logo-Dark.png'
Assert-NotContains $projectPath 'Logo-Light.png'
