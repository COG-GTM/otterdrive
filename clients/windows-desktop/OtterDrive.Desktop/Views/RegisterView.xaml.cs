using System.Windows.Controls;
using OtterDrive.Desktop.ViewModels;

namespace OtterDrive.Desktop.Views
{
    public partial class RegisterView : UserControl
    {
        public RegisterView()
        {
            InitializeComponent();
        }

        private void PasswordInput_PasswordChanged(object sender, System.Windows.RoutedEventArgs e)
        {
            if (DataContext is RegisterViewModel vm)
            {
                vm.Password = PasswordInput.Password;
            }
        }
    }
}
