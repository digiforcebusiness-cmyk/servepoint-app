import Flutter
import UIKit
import AppCoinsSDK

/// Native bridge to the AppCoins (Aptoide) iOS IAP SDK. Mirrors the Windows
/// Store IAP plugin: a MethodChannel with isAvailable / getPriceString /
/// purchase / checkLicense. Pro is a single non-consumable lifetime unlock.
///
/// The SDK is only active on EU devices, iOS >= 17.4, and when the app was NOT
/// installed from the Apple App Store; every method degrades gracefully (false
/// / nil / "notAvailable") otherwise.
public class AppCoinsIapPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.servepoint/appcoins_iap",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppCoinsIapPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall,
                     result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      Task {
        let available = await AppcSDK.isAvailable()
        DispatchQueue.main.async { result(available) }
      }

    case "getPriceString":
      guard let sku = self.sku(from: call) else {
        result(self.invalidArgs()); return
      }
      Task {
        let label = await self.priceLabel(sku: sku)
        DispatchQueue.main.async { result(label) }
      }

    case "purchase":
      guard let sku = self.sku(from: call) else {
        result(self.invalidArgs()); return
      }
      Task {
        let status = await self.purchase(sku: sku)
        DispatchQueue.main.async { result(status) }
      }

    case "checkLicense":
      guard let sku = self.sku(from: call) else {
        result(self.invalidArgs()); return
      }
      Task {
        let owned = await self.isOwned(sku: sku)
        DispatchQueue.main.async { result(owned) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Helpers

  private func sku(from call: FlutterMethodCall) -> String? {
    (call.arguments as? [String: Any])?["sku"] as? String
  }

  private func invalidArgs() -> FlutterError {
    FlutterError(code: "INVALID_ARGS", message: "sku is required", details: nil)
  }

  private func priceLabel(sku: String) async -> String? {
    guard await AppcSDK.isAvailable() else { return nil }
    do {
      let products = try await Product.products(for: [sku])
      return products.first?.priceLabel
    } catch {
      return nil
    }
  }

  private func purchase(sku: String) async -> String {
    guard await AppcSDK.isAvailable() else { return "notAvailable" }
    do {
      let products = try await Product.products(for: [sku])
      guard let product = products.first else { return "unknown" }
      let outcome = await product.purchase()
      switch outcome {
      case .success(let verification):
        switch verification {
        case .verified(let purchase):
          // Non-consumable: acknowledge (finish) but never consume.
          try? await purchase.finish()
          return "purchased"
        case .unverified:
          return "serverError"
        }
      case .pending:
        return "pending"
      case .userCancelled:
        return "cancelled"
      case .failed(let error):
        return self.mapError(error)
      }
    } catch {
      return "unknown"
    }
  }

  private func isOwned(sku: String) async -> Bool {
    guard await AppcSDK.isAvailable() else { return false }
    do {
      // A lifetime (non-consumable) is owned when its latest purchase exists
      // and has not been consumed.
      if let purchase = try await Purchase.latest(sku: sku) {
        return "\(purchase.state)".uppercased() != "CONSUMED"
      }
      return false
    } catch {
      return false
    }
  }

  private func mapError(_ error: Error) -> String {
    guard let e = error as? AppCoinsSDKError else { return "unknown" }
    switch e {
    case .networkError:
      return "networkError"
    default:
      return "serverError"
    }
  }
}

// ─── SDK-detail VERIFY notes (resolve on first Codemagic build) ───────────────
// 1. `purchase.state` is stringified and compared to "CONSUMED". If the SDK
//    exposes a typed enum (e.g. `.consumed`), switch to that.
// 2. Confirm the `AppCoinsSDKError` case `.networkError` exists; the `default`
//    branch catches the rest.
// 3. Confirm `finish()` acknowledges (does not consume) a non-consumable. If a
//    separate acknowledge API exists, call it instead.
