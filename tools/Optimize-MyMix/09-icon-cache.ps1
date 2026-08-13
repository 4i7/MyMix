# -----------------------------------------------------------------------------
# 9. Icon decoding/cache: shell/GDI icon extraction is expensive when the flyout is
#    recreated or the same app exists on multiple devices. Cache frozen ImageSources
#    by path/type/pixel-size and bound the cache to avoid unbounded retention.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/UI/Controls/ImageEx.cs' @'
using EarTrumpet.Interop;
using EarTrumpet.Interop.Helpers;
using EarTrumpet.UI.Helpers;
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace EarTrumpet.UI.Controls
{
    public class ImageEx : Image
    {
        public IAppIconSource SourceEx
        {
            get => (IAppIconSource)GetValue(SourceExProperty);
            set => SetValue(SourceExProperty, value);
        }

        public static readonly DependencyProperty SourceExProperty = DependencyProperty.Register(
            nameof(SourceEx), typeof(IAppIconSource), typeof(ImageEx), new PropertyMetadata(null, OnSourceExChanged));

        private const int MaxCachedIcons = 256;
        private static readonly ConcurrentDictionary<string, ImageSource> s_iconCache = new ConcurrentDictionary<string, ImageSource>(StringComparer.OrdinalIgnoreCase);
        private static readonly string s_windowsPath = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        private static readonly string s_systemPath = Environment.GetFolderPath(Environment.SpecialFolder.System);

        private uint _dpi;

        public ImageEx()
        {
            DpiChanged += OnDpiChanged;
            Loaded += OnLoaded;
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            _dpi = GetWindowDpi();
            RefreshSource();
        }

        private void OnDpiChanged(object sender, DpiChangedEventArgs e)
        {
            if (!IsLoaded) return;
            var nextDpi = GetWindowDpi();
            if (nextDpi == _dpi) return;
            _dpi = nextDpi;
            RefreshSource();
        }

        private void RefreshSource()
        {
            if (SourceEx == null || !IsLoaded)
            {
                Source = null;
                return;
            }

            Source = LoadImage(SourceEx.IconPath, SourceEx.IsDesktopApp);
        }

        private ImageSource LoadImage(string path, bool isDesktopApp)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;

            try
            {
                path = Environment.ExpandEnvironmentVariables(path.TrimStart('@'));
                var dpi = _dpi == 0 ? GetWindowDpi() : _dpi;
                var scale = dpi / 96.0;
                var cx = Math.Max(1, (int)Math.Round(Width * scale));
                var cy = Math.Max(1, (int)Math.Round(Height * scale));
                var cacheKey = (isDesktopApp ? "D|" : "M|") + cx + "x" + cy + "|" + path;

                if (s_iconCache.TryGetValue(cacheKey, out var cached)) return cached;

                var image = LoadImageCore(path, isDesktopApp, cx, cy);
                if (image == null) return null;
                if (image.CanFreeze) image.Freeze();

                if (s_iconCache.Count >= MaxCachedIcons) s_iconCache.Clear();
                return s_iconCache.GetOrAdd(cacheKey, image);
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"ImageEx LoadImage Failed: {path} {ex}");
                return null;
            }
        }

        private static ImageSource LoadImageCore(string path, bool isDesktopApp, int cx, int cy)
        {
            if (!isDesktopApp) return LoadShellIcon(path, false, cx, cy);

            var iconPath = new StringBuilder(path);
            var iconIndex = Shlwapi.PathParseIconLocationW(iconPath);
            if (iconIndex != 0)
            {
                using (var icon = IconHelper.LoadIconResource(iconPath.ToString(), Math.Abs(iconIndex), cx, cy))
                {
                    if (icon == null) return null;
                    return Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                }
            }

            if (path.Contains(",-")) path = path.Remove(path.LastIndexOf(",-") );
            return LoadShellIcon(path, true, cx, cy);
        }

        public static ImageSource LoadShellIcon(string path, bool isDesktopApp, int cx, int cy)
        {
            path = CanonicalizePath(path);
            IShellItem2 shellItem;
            try
            {
                shellItem = Shell32.SHCreateItemInKnownFolder(FolderIds.AppsFolder, Shell32.KF_FLAG_DONT_VERIFY, path, typeof(IShellItem2).GUID);
            }
            catch (Exception)
            {
                shellItem = Shell32.SHCreateItemFromParsingName(path, IntPtr.Zero, typeof(IShellItem2).GUID);
            }

            ((IShellItemImageFactory)shellItem).GetImage(new SIZE { cx = cx, cy = cy }, SIIGBF.SIIGBF_RESIZETOFIT, out var bmp);
            try
            {
                return Imaging.CreateBitmapSourceFromHBitmap(bmp, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            }
            finally
            {
                Gdi32.DeleteObject(bmp);
            }
        }

        private static string CanonicalizePath(string path)
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory) && directory.StartsWith(s_systemPath, StringComparison.InvariantCultureIgnoreCase))
            {
                path = Path.Combine(s_windowsPath, "sysnative", path.Substring(s_systemPath.Length + 1));
            }

            if (path.Equals("MicrosoftWindows.Client.CBS_cw5n1h2txyewy!CortanaUI", StringComparison.InvariantCultureIgnoreCase))
            {
                path = "MicrosoftWindows.Client.CBS_cw5n1h2txyewy!PackageMetadata";
            }
            return path;
        }

        private uint GetWindowDpi()
        {
            var source = PresentationSource.FromVisual(this) as HwndSource;
            return source == null ? 96u : User32.GetDpiForWindow(source.Handle);
        }

        private static void OnSourceExChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((ImageEx)d).RefreshSource();
    }
}
'@

Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'ConcurrentDictionary<string, ImageSource>'
Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'image.Freeze()'
Assert-Contains 'EarTrumpet/UI/Controls/ImageEx.cs' 'MaxCachedIcons = 256'
