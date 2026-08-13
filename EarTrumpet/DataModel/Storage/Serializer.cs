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