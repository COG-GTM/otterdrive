using System.Windows;
using OtterDrive.Desktop.Services;
using OtterDrive.Desktop.ViewModels;
using OtterDrive.Desktop.Views;

namespace OtterDrive.Desktop
{
    /// <summary>Application entry point; wires up services and shows the shell window.</summary>
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            AppSettings settings = AppSettings.Load();
            var session = new SessionState(settings.PersistTokens);
            session.TryRestore();

            var api = new OtterDriveApiClient(settings, session);
            var mainViewModel = new MainViewModel(api, session);

            var window = new MainWindow { DataContext = mainViewModel };
            window.Show();
        }
    }
}
