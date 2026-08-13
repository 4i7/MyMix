using EarTrumpet.DataModel.WindowsAudio;
using System.Collections.ObjectModel;

namespace EarTrumpet.DataModel.Audio
{
    public interface IAudioDeviceSession : IStreamWithVolumeControl
    {
        IAudioDevice Parent { get; }
        string DisplayName { get; }
        string ExeName { get; }
        string IconPath { get; }
        bool IsDesktopApp { get; }
        bool IsSystemSoundsSession { get; }
        int ProcessId { get; }
        string AppId { get; }
        SessionState State { get; }
        ObservableCollection<IAudioDeviceSession> Children { get; }
    }
}