using EarTrumpet.DataModel.Audio;
using EarTrumpet.DataModel.WindowsAudio;
using EarTrumpet.DataModel.WindowsAudio.Internal;
using EarTrumpet.Extensions;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Media;

namespace EarTrumpet.UI.ViewModels
{
    public class AppItemViewModel : AudioSessionViewModel, IAppItemViewModel
    {
        public class ExeNameComparer : IComparer<IAppItemViewModel>
        {
            public int Compare(IAppItemViewModel one, IAppItemViewModel two) =>
                string.Compare(one.ExeName, two.ExeName, StringComparison.Ordinal);
        }

        public static readonly ExeNameComparer CompareByExeName = new ExeNameComparer();
        private static readonly bool s_isMovableOs = Environment.OSVersion.IsAtLeast(OSVersions.RS4);

        private readonly IAudioDeviceSession _session;
        private readonly WeakReference<DeviceViewModel> _parent;
        private bool _disposed;

        public Color Background { get; private set; }
        public string DisplayName => _session.DisplayName;
        public string ExeName => _session.ExeName;
        public string AppId => _session.AppId;
        public string IconPath => _session.IconPath;
        public bool IsDesktopApp => _session.IsDesktopApp;
        public bool IsExpanded { get; private set; }
        public int ProcessId => _session.ProcessId;
        public ObservableCollection<IAppItemViewModel> ChildApps { get; private set; }
        public bool IsMovable => !_session.IsSystemSoundsSession && s_isMovableOs;
        public string PersistedOutputDevice => _session.Parent.Parent is IAudioDeviceManagerWindowsAudio manager ? manager.GetDefaultEndPoint(ProcessId) : string.Empty;

        public char IconText
        {
            get
            {
                var name = DisplayName;
                if (string.IsNullOrWhiteSpace(name)) return '?';
                foreach (var c in name)
                {
                    if (char.IsLetterOrDigit(c)) return char.ToUpperInvariant(c);
                }
                return '?';
            }
        }

        public IDeviceViewModel Parent
        {
            get
            {
                _parent.TryGetTarget(out var parent);
                return parent;
            }
        }

        internal AppItemViewModel(DeviceViewModel parent, IAudioDeviceSession session, bool isChild = false) : base(session)
        {
            IsExpanded = isChild;
            _session = session;
            _parent = new WeakReference<DeviceViewModel>(parent);
            _session.PropertyChanged += Session_PropertyChanged;

            if (_session.Children != null)
            {
                _session.Children.CollectionChanged += Children_CollectionChanged;
                ChildApps = new ObservableCollection<IAppItemViewModel>();
                foreach (var child in _session.Children)
                {
                    ChildApps.Add(new AppItemViewModel(parent, child, true));
                }
            }
        }

        private void Session_PropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(_session.DisplayName)) RaisePropertyChanged(nameof(DisplayName));
            else if (e.PropertyName == nameof(_session.IconPath)) RaisePropertyChanged(nameof(IconPath));
        }

        private void Children_CollectionChanged(object sender, NotifyCollectionChangedEventArgs e)
        {
            if (!_parent.TryGetTarget(out var parent) || ChildApps == null) return;

            if (e.Action == NotifyCollectionChangedAction.Add)
            {
                Debug.Assert(e.NewItems.Count == 1);
                ChildApps.Add(new AppItemViewModel(parent, (IAudioDeviceSession)e.NewItems[0], true));
                return;
            }

            if (e.Action == NotifyCollectionChangedAction.Remove)
            {
                Debug.Assert(e.OldItems.Count == 1);
                var id = ((IAudioDeviceSession)e.OldItems[0]).Id;
                for (var i = 0; i < ChildApps.Count; i++)
                {
                    if (ChildApps[i].Id != id) continue;
                    (ChildApps[i] as IDisposable)?.Dispose();
                    ChildApps.RemoveAt(i);
                    return;
                }
                return;
            }

            throw new NotImplementedException();
        }

        public void MoveToDevice(string id, bool hide) => ((IAudioDeviceSessionInternal)_session).MoveToDevice(id, hide);

        public override void UpdatePeakValueForeground()
        {
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) ChildApps[i].UpdatePeakValueForeground();
            }
            base.UpdatePeakValueForeground();
        }

        public void UpdatePeakValueBackground()
        {
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) ChildApps[i].UpdatePeakValueBackground();
            }
            ((IAudioDeviceSessionInternal)_session).UpdatePeakValueBackground();
        }

        public bool DoesGroupWith(IAppItemViewModel app) => AppId == app.AppId;

        public override void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _session.PropertyChanged -= Session_PropertyChanged;
            if (_session.Children != null) _session.Children.CollectionChanged -= Children_CollectionChanged;
            if (ChildApps != null)
            {
                for (var i = 0; i < ChildApps.Count; i++) (ChildApps[i] as IDisposable)?.Dispose();
            }
            base.Dispose();
        }

        public override string ToString() => IsMuted
            ? Properties.Resources.AppOrDeviceMutedFormatAccessibleText.Replace("{Name}", DisplayName)
            : Properties.Resources.AppOrDeviceFormatAccessibleText.Replace("{Name}", DisplayName).Replace("{Volume}", Volume.ToString());
    }
}