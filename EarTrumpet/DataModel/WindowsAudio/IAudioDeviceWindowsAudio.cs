using EarTrumpet.DataModel.Audio;

namespace EarTrumpet.DataModel.WindowsAudio
{
    public interface IAudioDeviceWindowsAudio : IAudioDevice
    {
        string EnumeratorName { get; }
        string InterfaceName { get; }
        string DeviceDescription { get; }
    }
}