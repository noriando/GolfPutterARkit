import UIKit
import ARKit
import os         // Added for Logger
import Foundation // Added for Bundle

// Logger instance for AppDelegate
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Check if ARKit is supported
        guard ARWorldTrackingConfiguration.isSupported else {
            logger.error("ARWorldTrackingConfiguration is not supported")
            return true
        }
        
        // Create window programmatically
        window = UIWindow(frame: UIScreen.main.bounds)
        
        // Set up the root view controller
        let viewController = ViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        
        return true
    }
}
