namespace EarTrumpet.DataModel.Storage
{
    public class StorageFactory
    {
        private static readonly ISettingsBag s_globalSettings = new Internal.RegistrySettingsBag();

        public static ISettingsBag GetSettings(string nameSpace = null)
        {
            return (nameSpace == null) ? s_globalSettings :
                new Internal.NamespacedSettingsBag(nameSpace, s_globalSettings);
        }
    }
}