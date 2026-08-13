using EarTrumpet.Extensions;
using EarTrumpet.Interop;
using EarTrumpet.Interop.MMDeviceAPI;
using System;

namespace EarTrumpet.DataModel.WindowsAudio.Internal
{
    class Helpers
    {
        public static float ReadPeakValue(IAudioMeterInformation meter)
        {
            if (meter == null)
            {
                return 0f;
            }

            try
            {
                return meter.GetPeakValue();
            }
            catch (Exception ex) when (ex.Is(HRESULT.AUDCLNT_E_DEVICE_INVALIDATED))
            {
                return 0f;
            }
        }
    }
}