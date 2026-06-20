import Flutter
import UIKit
import AppCoinsSDK

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppcSDK.initialize()
    drainUnfinishedPurchases()
    if let url = launchOptions?[.url] as? URL, AppcSDK.handle(redirectURL: url) {
      return true
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    AppcSDK.initialize()
    if AppcSDK.handle(redirectURL: url) { return true }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppCoinsIapPlugin") {
      AppCoinsIapPlugin.register(with: registrar)
    }
  }

  /// Finalize any purchase interrupted before `finish()` (e.g. app killed
  /// mid-flow). Acknowledging a non-consumable here keeps ownership intact.
  private func drainUnfinishedPurchases() {
    Task {
      guard await AppcSDK.isAvailable() else { return }
      if let purchases = try? await Purchase.unfinished() {
        for purchase in purchases { try? await purchase.finish() }
      }
    }
  }
}
