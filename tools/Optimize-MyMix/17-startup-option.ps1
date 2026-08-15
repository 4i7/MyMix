# Preserve the optional Windows sign-in startup control without adding polling or startup-time
# registry writes. Registry access only happens when the user opens/toggles the tray option.

$appPath = "EarTrumpet/App.xaml.cs"
$app = Read-Text $appPath

if (-not $app.Contains("using Microsoft.Win32;")) {
    $anchor = "using EarTrumpet.UI.Views;"
    if (-not $app.Contains($anchor)) { throw "App using insertion anchor was not found." }
    $app = $app.Replace($anchor, $anchor + "`r`nusing Microsoft.Win32;")
}

if (-not $app.Contains("private static bool IsStartupRegistrationEnabled()")) {
    $anchor = "        private void ContinueStartup()"
    if (-not $app.Contains($anchor)) { throw "App startup helper insertion anchor was not found." }
    $methods = Read-Text "tools/Optimize-MyMix/Templates/startup-methods.txt"
    $app = $app.Replace($anchor, $methods + $anchor)
}

if (-not $app.Contains("Command = new RelayCommand(ToggleStartupRegistration)")) {
    $anchor = "                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.SettingsWindowText, Command = new RelayCommand(_settingsWindow.OpenOrBringToFront) },"
    if (-not $app.Contains($anchor)) { throw "App startup menu insertion anchor was not found." }
    $menuItem = Read-Text "tools/Optimize-MyMix/Templates/startup-menu-item.txt"
    $app = $app.Replace($anchor, $anchor + "`r`n" + $menuItem.TrimEnd("`r", "`n"))
}

Write-Text $appPath $app

Assert-Contains $appPath "using Microsoft.Win32;"
Assert-Contains $appPath "private static bool IsStartupRegistrationEnabled()"
Assert-Contains $appPath "private static void ToggleStartupRegistration()"
Assert-Contains $appPath "private static void SetStartupRegistration(bool enabled)"
Assert-Contains $appPath "Software\Microsoft\Windows\CurrentVersion\Run"
Assert-Contains $appPath "Windows サインイン時に MyMix を起動"
Assert-Contains $appPath "Start MyMix at Windows sign-in"
Assert-Contains $appPath "Command = new RelayCommand(ToggleStartupRegistration)"
Assert-NotContains $appPath "EnsureStartupRegistration()"
