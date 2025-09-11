import UIKit
import ARKit
import os         // Added for Logger
import Foundation // Added for Bundle

// Logger instance for AppDelegate
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var privacyView: UIView?
    
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
    
    // MARK: - Background Privacy Protection
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Called when the app is about to move from active to inactive state
        // This happens when going to background or when interrupted (e.g., incoming call)
        addPrivacyOverlay()
        logger.info("Privacy overlay added - app transitioning to inactive state")
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Called when the app becomes active again
        removePrivacyOverlay()
        logger.info("Privacy overlay removed - app became active")
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Additional protection when app fully enters background
        addPrivacyOverlay()
        logger.info("App entered background - privacy overlay ensured")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called when app is about to enter foreground
        logger.info("App will enter foreground")
    }
    
    // MARK: - Privacy Overlay Methods
    
    private func addPrivacyOverlay() {
        guard let window = window, privacyView == nil else { return }
        
        // Create privacy overlay view
        privacyView = UIView(frame: window.bounds)
        privacyView?.backgroundColor = UIColor.systemBackground
        
        // Add your app logo or generic content
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Try to load app icon or use a placeholder
        if let appIcon = UIImage(named: "AppIcon") ?? createPlaceholderImage() {
            imageView.image = appIcon
        }
        
        privacyView?.addSubview(imageView)
        
        // Center the image
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: privacyView!.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: privacyView!.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 100),
            imageView.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        // Add the overlay to the window
        window.addSubview(privacyView!)
        
        // Bring to front to ensure it covers everything
        window.bringSubviewToFront(privacyView!)
    }
    
    private func removePrivacyOverlay() {
        privacyView?.removeFromSuperview()
        privacyView = nil
    }
    
    private func createPlaceholderImage() -> UIImage? {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.systemGray.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        // Add app name or placeholder text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.label
        ]
        
        let text = Bundle.main.displayName ?? "App"
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Bundle Extension for Display Name
extension Bundle {
    var displayName: String? {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
               object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
