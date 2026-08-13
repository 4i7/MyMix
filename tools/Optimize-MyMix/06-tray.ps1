# -----------------------------------------------------------------------------
# 6. Tray work: stop registry/DPI/hash-string work on every mouse move and stop
#    shell icon/tooltip updates for volume changes inside the same icon bucket.
# -----------------------------------------------------------------------------
$taskbarPath = 'EarTrumpet/UI/Helpers/TaskbarIconSource.cs'
$taskbar = Read-Text $taskbarPath
$taskbar = $taskbar.Replace('        private string _hash;', '        private int? _hash;')
$taskbar = [regex]::Replace($taskbar, '(?ms)        private string GetHash\(\) =>.*?;', @'
        private int GetHash()
        {
            unchecked
            {
                var hash = (int)_kind;
                hash = (hash * 397) ^ (int)WindowsTaskbar.Dpi;
                hash = (hash * 397) ^ (SystemSettings.IsSystemLightTheme ? 1 : 0);
                hash = (hash * 397) ^ (System.Windows.SystemParameters.HighContrast ? 1 : 0);
                if (System.Windows.SystemParameters.HighContrast)
                {
                    hash = (hash * 397) ^ (_isMouseOver ? 1 : 0);
                }
                return hash;
            }
        }
'@)
Write-Text $taskbarPath $taskbar

$shellPath = 'EarTrumpet/UI/Helpers/ShellNotifyIcon.cs'
$shell = Read-Text $shellPath
# WM_MOUSEMOVE already calls OnNotifyIconMouseMove, which calls OnMouseOverChanged only on an actual state transition.
$shell = [regex]::Replace($shell, '(?m)^\s*IconSource\.CheckForUpdate\(\);\r?\n(?=\s*break;\r?\n\s*\})', '')
Write-Text $shellPath $shell
