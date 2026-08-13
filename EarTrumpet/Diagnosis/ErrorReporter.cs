using System;
using System.Diagnostics;

namespace EarTrumpet.Diagnosis
{
    class ErrorReporter
    {
        private readonly CircularBufferTraceListener _listener;

        public ErrorReporter(AppSettings settings)
        {
            _listener = new CircularBufferTraceListener();
            Trace.Listeners.Clear();
            Trace.Listeners.Add(_listener);
        }

        public void DisplayDiagnosticData()
        {
            LocalDataExporter.DumpAndShowData(_listener.GetLogText());
        }

        public static void LogWarning(Exception ex)
        {
            Trace.WriteLine($"## Warning ##: {ex}");
        }
    }
}