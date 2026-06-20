# iOS AppCoins IAP — Lifetime Pro Unlock (Aptoide distribution)

**Date:** 2026-06-19
**Status:** Approved design, pending implementation plan
**Author:** ServePoint

## Goal

Sell **ServePoint Pro** on the iOS build distributed through **Aptoide** (alternative
app marketplace), using the **AppCoins iOS SDK** (`AppCoinsSDK`). Apple's StoreKit
in-app purchases do not function on alternative marketplaces, so AppCoins is the
billing system for the iOS/Aptoide build.

## Decisions (locked)

| Question | Decision | Rationale |
|---|---|---|
| iOS distribution | **Aptoide only** (not the Apple App Store) | AppCoins is the single iOS billing system; no runtime dual-billing detection needed. |
| Pro product model | **One-time lifetime unlock** (non-consumable) | AppCoins iOS supports only one-time products — **no auto-renewing subscriptions** (Purchase states are only PENDING → ACKNOWLEDGED → CONSUMED). |
| Price | **$99** (set in Aptoide Connect product config) | Mirrors the Windows lifetime price. App displays the live `priceLabel`, falling back to `$99`. |
| Architecture | **Approach A** — native Swift plugin + Flutter `MethodChannel` | Mirrors the existing Windows IAP integration; no new dependencies. |

## Key SDK facts (verified from docs)

- Package: Swift Package Manager `https://github.com/Catappult/appcoins-sdk-ios.git`
- Import: `import AppCoinsSDK`
- Availability constraint: the SDK is only active on **EU devices, iOS ≥ 17.4, and
  only when the app was NOT installed from the Apple App Store**.
- Core API (async/await):
  - `AppcSDK.initialize()` — call at every app entry point before any SDK use
  - `AppcSDK.handle(redirectURL:)` — deep-link/payment redirect handling
  - `await AppcSDK.isAvailable()` — gate before any purchase
  - `try await Product.products(for: [sku])` — query products; `Product` has
    `sku`, `title`, `priceLabel`, `priceValue`, `priceCurrency`, `priceSymbol`
  - `await product.purchase()` → `PurchaseResult` (`.success(verificationResult)`,
    `.pending`, `.userCancelled`, `.failed(error)`); verified case yields a
    `Purchase` with `try await purchase.finish()`
  - `try await Purchase.latest(sku:)`, `Purchase.all()`, `Purchase.unfinished()`
  - `Purchase` has `uid`, `sku`, `state`, `orderUid`, `payload`, `verification`
  - `AppCoinsSDKError`: `networkError`, `systemError`, `notEntitled`,
    `productUnavailable`, `purchaseNotAllowed`, `unknown`

## Architecture

Mirror the Windows IAP structure so both native integrations are structurally
identical.

| Layer | Windows (existing) | iOS (new) |
|---|---|---|
| Native plugin | `windows/runner/store_iap_plugin.cpp` | `ios/Runner/AppCoinsIapPlugin.swift` |
| Channel name | `com.servepoint/store_iap` | `com.servepoint/appcoins_iap` |
| Dart service | `lib/features/subscription/windows_iap_service.dart` | `lib/features/subscription/appcoins_iap_service.dart` |
| Dart provider | `lib/features/subscription/windows_iap_provider.dart` | `lib/features/subscription/appcoins_iap_provider.dart` |
| Pro bool provider | `windowsIsProProvider` | `appCoinsIsProProvider` |

`isProProvider` (`lib/features/subscription/subscription_provider.dart`) gains an iOS
branch routing to `appCoinsIsProProvider` instead of the dead RevenueCat path. The
existing `kForcePaywall` dev flag continues to short-circuit to `false` first.

## Component design

### Native: `AppCoinsIapPlugin.swift`

Registered from `AppDelegate`. Implements a `FlutterMethodChannel`
(`com.servepoint/appcoins_iap`) with four methods, parallel to the Windows plugin:

- `isAvailable` → `await AppcSDK.isAvailable()` → `Bool`
- `getPriceString` (arg `sku`) → `Product.products(for: [sku])` → first product's
  `priceLabel` (or `nil`)
- `purchase` (arg `sku`) → `await product.purchase()`; on `.success(.verified)` call
  `try await purchase.finish()` to acknowledge (NEVER consume — non-consumable),
  return a status string: `purchased`, `alreadyPurchased`, `cancelled`,
  `pending`, `networkError`, `serverError`, or `unknown`
- `checkLicense` (arg `sku`) → `try await Purchase.latest(sku:)`; return `true` when
  an owned, acknowledged, non-consumed purchase exists

### iOS configuration

- Add SwiftPM dependency `appcoins-sdk-ios`.
- **Keychain Sharing** capability → group `com.aptoide.appcoins-wallet`.
- `Info.plist`: URL type with scheme `$(PRODUCT_BUNDLE_IDENTIFIER).iap` (role Editor);
  `MKSellsDigitalGoods = YES`.
- `SceneDelegate.swift` + `AppDelegate.swift`: call `AppcSDK.initialize()` and
  `AppcSDK.handle(redirectURL:)` in the URL/launch entry points.
- On launch, drain `Purchase.unfinished()` and `finish()` each (finalize interrupted
  purchases).

### Dart: `AppCoinsIapService`

Shape parallels `WindowsIAPService`:

- `static bool get isSupported` → `!kIsWeb && Platform.isIOS`
- `bool get isPro`, `bool get isStoreAvailable`
- `Future<void> initialize()` → `isAvailable` then `checkLicense`
- `Future<String?> fetchLifetimePriceString()`
- `Future<String?> buyLifetime()` → returns `null` on success/cancel, else an error
  message (mapped from status / `AppCoinsSDKError`)
- `Future<bool> restore()` → re-runs `checkLicense`

### Dart: providers & wiring

- `appCoinsIapProvider` (`AsyncNotifierProvider`) parallel to `windowsIAPProvider`.
- `appCoinsIsProProvider` → false off-iOS; otherwise service `isPro`.
- `isProProvider` adds: `if (Platform.isIOS) return ref.watch(appCoinsIsProProvider);`.
- Const `kAppCoinsLifetimeSku` (initial value `servepoint_pro_lifetime`) — must match
  the SKU created in Aptoide Connect.
- Paywall reuses the existing lifetime card on iOS with a `$99` fallback price.

## Error handling & availability

- `AppcSDK.isAvailable() == false` (non-EU, iOS < 17.4, or App-Store install) →
  treat as **not Pro**; the paywall shows but the purchase action surfaces a clear
  "Pro purchases aren't available on this device" message. Same defensive stance as
  the Windows `isStoreAvailable` gate.
- Map `AppCoinsSDKError` cases to friendly messages, mirroring the `buyPro`/
  `buyLifetime` status switch on Windows.
- All native SDK calls run async; marshal results back to the platform thread before
  replying on the channel (Swift async/await + `result(...)` on main).

## Testing

- AppCoins test mode: set **Marketplaces** build setting to `com.aptoide.ios.store`
  and the scheme Run → Distribution to `com.aptoide.ios.store`.
- Use the existing `--dart-define=FORCE_PAYWALL=true` flag to exercise the paywall UI
  on the simulator without a real wallet.
- Verify: price label shows `$99` (or live), purchase dialog opens, ownership
  persists across relaunch (`checkLicense`), and an interrupted purchase is finalized
  by the `Purchase.unfinished()` drain on next launch.

## Open implementation detail to verify

- Confirm, against the AppCoins SDK source / sample, the exact acknowledge-vs-consume
  semantics of `purchase.finish()` for a **non-consumable**: a lifetime purchase must
  be acknowledged (so it is not auto-refunded) but never consumed (so ownership
  persists). Adjust `purchase`/`checkLicense` accordingly.

## Out of scope

- Apple App Store distribution and Apple StoreKit / RevenueCat on iOS.
- Auto-renewing subscriptions on iOS (not supported by AppCoins).
- AppArena marketplace (only Aptoide for now).
- Android billing changes.
