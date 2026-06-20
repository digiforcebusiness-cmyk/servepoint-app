import Flutter
import UIKit
import AppCoinsSDK

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    AppcSDK.initialize()
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      _ = AppcSDK.handle(redirectURL: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    AppcSDK.initialize()
    if let url = URLContexts.first?.url, AppcSDK.handle(redirectURL: url) { return }
    super.scene(scene, openURLContexts: URLContexts)
  }
}

// VERIFY on first Codemagic build: confirm FlutterSceneDelegate exposes these
// overridable scene methods in Flutter 3.27. If not, move the AppcSDK.handle
// calls into AppDelegate's `open url:` (which already covers payment redirects)
// and keep SceneDelegate minimal.
