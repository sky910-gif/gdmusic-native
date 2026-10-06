import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AudioSession.activate()
        RemoteCommandController.shared.register()

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .black
        let search = SearchViewController()
        window?.rootViewController = UINavigationController(rootViewController: search)
        window?.makeKeyAndVisible()
        return true
    }
}
