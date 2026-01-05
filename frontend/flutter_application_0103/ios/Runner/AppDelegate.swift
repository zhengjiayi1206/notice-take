import Flutter
import UIKit
import QuartzCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if #available(iOS 15.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        if let windowScene = scene as? UIWindowScene {
          windowScene.preferredFrameRateRange = CAFrameRateRange(
            minimum: 120,
            maximum: 120,
            preferred: 120
          )
        }
      }
    }

    return result
  }
}
