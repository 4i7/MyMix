# Preserve MyMix's optional Windows sign-in startup control without adding any polling or
# startup-time registry writes. The registry is touched only when the user toggles the menu item.

$appPath = 'EarTrumpet/App.xaml.cs'
$app = Read-Text $appPath

if (-not $app.Contains('using Microsoft.Win32;')) {
    $anchor = 'using EarTrumpet.UI.Views;'
    if (-not $app.Contains($anchor)) { throw 'App using insertion anchor was not found.' }
    $app = $app.Replace($anchor, $anchor + "`r`nusing Microsoft.Win32;")
}

if (-not $app.Contains('private static bool IsStartupRegistrationEnabled()')) {
    $anchor = '        private void ContinueStartup()'
    if (-not $app.Contains($anchor)) { throw 'App startup helper insertion anchor was not found.' }
    $methods = @'
        private static bool IsStartupRegistrationEnabled()
        {
            const string runKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
            const string valueName = "MyMix";

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(runKeyPath, writable: false))
                {
                    return runKey?.GetValue(valueName) != null;
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"App IsStartupRegistrationEnabled failed: {ex}");
                return false;
            }
        }

        private static void ToggleStartupRegistration()
        {
            SetStartupRegistration(!IsStartupRegistrationEnabled());
        }

        private static void SetStartupRegistration(bool enabled)
        {
            const string runKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
            const string valueName = "MyMix";

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(runKeyPath, writable: true) ?? Registry.CurrentUser.CreateSubKey(runKeyPath))
                {
                    if (runKey == null)
                    {
                        return;
                    }

                    if (enabled)
                    {
                        var executablePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        runKey.SetValue(valueName, $"\"{executablePath}\"");
                    }
                    else
                    {
                        runKey.DeleteValue(valueName, throwOnMissingValue: false);
                    }
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"App SetStartupRegistration failed: {ex}");
            }
        }

'@
    $app = $app.Replace($anchor, $methods + $anchor)
}

if (-not $app.Contains('Command = new RelayCommand(ToggleStartupRegistration)')) {
    $anchor = '                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.SettingsWindowText, Command = new RelayCommand(_settingsWindow.OpenOrBringToFront) },'
    if (-not $app.Contains($anchor)) { throw 'App startup menu insertion anchor was not found.' }
    $menuItem = @'
                    new ContextMenuItem
                    {
                        DisplayName = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja"
                            ? "Windows サインイン時に MyMix を起動"
                            : "Start MyMix at Windows sign-in",
                        IsChecked = IsStartupRegistrationEnabled(),
                        Command = new RelayCommand(ToggleStartupRegistration),
                    },
'@
    $app = $app.Replace($anchor, $anchor + "`r`n" + $menuItem.TrimEnd("`r", "`n"))
}

Write-Text $appPath $app

Assert-Contains $appPath 'using Microsoft.Win32;'
Assert-Contains $appPath 'private static bool IsStartupRegistrationEnabled()'
Assert-Contains $appPath 'private static void ToggleStartupRegistration()'
Assert-Contains $appPath 'private static void SetStartupRegistration(bool enabled)'
Assert-Contains $appPath '@"Software\Microsoft\Windows\CurrentVersion\Run"'
Assert-Contains $appPath 'Windows サインイン時に MyMix を起動'
Assert-Contains $appPath 'Start MyMix at Windows sign-in'
Assert-Contains $appPath 'Command = new RelayCommand(ToggleStartupRegistration)'
Assert-NotContains $appPath 'EnsureStartupRegistration()'
