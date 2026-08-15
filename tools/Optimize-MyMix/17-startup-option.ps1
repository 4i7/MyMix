# Preserve MyMix's optional Windows sign-in startup control without adding any polling or
# startup-time registry writes. The registry is touched only when the user toggles the menu item.

function Ensure-StartupResxString([string]$RelativePath, [string]$Name, [string]$Value) {
    $text = Read-Text $RelativePath
    $needle = '<data name="' + $Name + '"'
    if ($text.Contains($needle)) { return }

    $escaped = [Security.SecurityElement]::Escape($Value)
    $entry = '  <data name="' + $Name + '" xml:space="preserve">' + "`r`n" +
             '    <value>' + $escaped + '</value>' + "`r`n" +
             '  </data>' + "`r`n"
    if (-not $text.Contains('</root>')) { throw ($RelativePath + ' is not a valid resx document.') }
    Write-Text $RelativePath ($text.Replace('</root>', $entry + '</root>'))
}

Ensure-StartupResxString 'EarTrumpet/Properties/Resources.resx' 'SettingsStartWithWindowsText' 'Start MyMix at Windows sign-in'
Ensure-StartupResxString 'EarTrumpet/Properties/Resources.ja-JP.resx' 'SettingsStartWithWindowsText' 'Windows サインイン時に MyMix を起動'

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

if (-not $app.Contains('SettingsStartWithWindowsText')) {
    $anchor = '                    new ContextMenuItem { DisplayName = EarTrumpet.Properties.Resources.SettingsWindowText, Command = new RelayCommand(_settingsWindow.OpenOrBringToFront) },'
    if (-not $app.Contains($anchor)) { throw 'App startup menu insertion anchor was not found.' }
    $menuItem = @'
                    new ContextMenuItem
                    {
                        DisplayName = EarTrumpet.Properties.Resources.ResourceManager.GetString("SettingsStartWithWindowsText", System.Globalization.CultureInfo.CurrentUICulture) ?? "Start MyMix at Windows sign-in",
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
Assert-Contains $appPath 'SettingsStartWithWindowsText'
Assert-Contains $appPath 'Command = new RelayCommand(ToggleStartupRegistration)'
Assert-NotContains $appPath 'EnsureStartupRegistration()'
