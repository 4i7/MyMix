# Keep the 30 FPS peak-meter implementation while avoiding Timer ambiguity.
# System.Timers.Timer remains the cadence source; Interlocked is fully-qualified.
$path = 'EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs'
$text = Read-Text $path
$text = [regex]::Replace($text, '(?m)^using System\.Threading;\r?\n', '')
$text = $text.Replace('Interlocked.Exchange(', 'System.Threading.Interlocked.Exchange(')
Write-Text $path $text

Assert-Contains $path 'new Timer(1000.0 / 30.0)'
Assert-Contains $path 'System.Threading.Interlocked.Exchange(ref _peakUpdateRunning, 1)'
Assert-Contains $path 'DispatcherPriority.Render'
Assert-NotContains $path 'using System.Threading;'
