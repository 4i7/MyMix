using System;
using System.Diagnostics;

namespace EarTrumpet.Diagnosis
{
    class ErrorReporter
    {
        public ErrorReporter(AppSettings settings)
        {
        }

        public void DisplayDiagnosticData()
        {
            LocalDataExporter.DumpAndShowData(null);
        }

        [Conditional("DEBUG")]
        public static void LogWarning(Exception ex)
        {
            Debug.WriteLine($"## Warning ##: {ex}");
        }
    }
}