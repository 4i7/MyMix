using System;

namespace EarTrumpet.Extensions
{
    public static class FloatExtensions
    {
        private const double CurveFactor = 3.5;
        private static readonly double InverseCurveScale = Math.Exp(-CurveFactor);
        public static readonly float MuteThreshold = (float)(Math.Exp(CurveFactor * 0.01) * InverseCurveScale);

        public static int ToVolumeInt(this float val)
        {
            return Convert.ToInt32(Math.Round(val * 100, MidpointRounding.AwayFromZero));
        }

        public static float Bound(this float val, float min, float max)
        {
            return Math.Max(min, Math.Min(max, val));
        }

        public static float ToLogVolume(this float val)
        {
            return ((float)(Math.Exp(CurveFactor * val) * InverseCurveScale)).Bound(0, 1f);
        }

        public static float ToDisplayVolume(this float val)
        {
            if (val <= 0)
            {
                return 0;
            }
            return ((float)((Math.Log(val) + CurveFactor) / CurveFactor)).Bound(0, 1f);
        }
    }
}