# -----------------------------------------------------------------------------
# 5. Registry/settings hot path: reuse serializers and avoid writable registry opens
#    for reads.
# -----------------------------------------------------------------------------
Write-Text 'EarTrumpet/DataModel/Storage/Serializer.cs' @'
using System.IO;
using System.Xml;
using System.Xml.Serialization;

namespace EarTrumpet.DataModel.Storage
{
    public class Serializer
    {
        private static class Cache<T>
        {
            internal static readonly XmlSerializer Instance = new XmlSerializer(typeof(T));
        }

        public static T FromString<T>(string data)
        {
            using (var reader = new StringReader(data))
            {
                return (T)Cache<T>.Instance.Deserialize(reader);
            }
        }

        public static string ToString<T>(string key, T value)
        {
            using (var stringWriter = new StringWriter())
            using (var writer = XmlWriter.Create(stringWriter))
            {
                Cache<T>.Instance.Serialize(writer, value);
                return stringWriter.ToString();
            }
        }
    }
}
'@

$registryPath = 'EarTrumpet/DataModel/Storage/Internal/RegistrySettingsBag.cs'
$registry = Read-Text $registryPath
$registry = [regex]::Replace($registry, '(?ms)        public bool HasKey\(string key\)\s*\{.*?\n        \}(?=\s*public T Get<T>)', @'
        public bool HasKey(string key)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey(s_earTrumpetKey, false))
            {
                return regKey?.GetValue(key) != null;
            }
        }
'@)
$registry = [regex]::Replace($registry, '(?ms)        static T ReadSetting<T>\(string key, T defaultValue\)\s*\{.*?\n        \}(?=\s*static void WriteSetting)', @'
        static T ReadSetting<T>(string key, T defaultValue)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey(s_earTrumpetKey, false))
            {
                if (regKey == null) return defaultValue;
                try
                {
                    var value = regKey.GetValue(key);
                    return value == null ? defaultValue : (T)value;
                }
                catch (Exception)
                {
                    return defaultValue;
                }
            }
        }
'@)
Write-Text $registryPath $registry
