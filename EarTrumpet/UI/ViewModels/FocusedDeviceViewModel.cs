using System;
using System.Collections.ObjectModel;

namespace EarTrumpet.UI.ViewModels
{
    class FocusedDeviceViewModel : IFocusedViewModel
    {
        public event Action RequestClose { add { } remove { } }
        public string DisplayName { get; }
        public ObservableCollection<ToolbarItemViewModel> Toolbar { get; } = new ObservableCollection<ToolbarItemViewModel>();
        public ObservableCollection<object> Addons { get; } = new ObservableCollection<object>();
        public bool IsApplicable => false;

        public FocusedDeviceViewModel(DeviceCollectionViewModel mainViewModel, DeviceViewModel device)
        {
            DisplayName = device.DisplayName;
        }

        public void Closing() { }
    }
}