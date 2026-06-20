# iOS AppCoins IAP (Lifetime Pro Unlock) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell a $99 one-time lifetime ServePoint Pro unlock on the Aptoide-distributed iOS build via the AppCoins SDK.

**Architecture:** A native Swift plugin (`AppCoinsIapPlugin.swift`) wraps `AppCoinsSDK` and talks to Dart over a `MethodChannel` (`com.servepoint/appcoins_iap`). A Dart `AppCoinsIapService` + `appCoinsIsProProvider` mirror the existing Windows IAP layer, and `isProProvider` routes to it on iOS. Structurally identical to the Windows integration.

**Tech Stack:** Flutter, Riverpod, Swift (async/await), AppCoinsSDK (`github.com/Catappult/appcoins-sdk-ios`).

## Global Constraints

- iOS distribution is **Aptoide only** — AppCoins is the sole iOS billing system.
- Pro = **one-time lifetime unlock** (non-consumable). AppCoins iOS has **no subscriptions**.
- Channel name: **`com.servepoint/appcoins_iap`** (exact).
- SKU const `kAppCoinsLifetimeSku` initial value **`servepoint_pro_lifetime`** — must match the Aptoide Connect product SKU.
- Price displayed from live `priceLabel`, fallback **`$99`**.
- Keychain Sharing group **`com.aptoide.appcoins-wallet`**; URL scheme **`$(PRODUCT_BUNDLE_IDENTIFIER).iap`**; Info.plist **`MKSellsDigitalGoods = YES`**.
- AppCoins SDK only active on **EU devices, iOS ≥ 17.4, non-App-Store install**.
- **Build environment:** Dart tasks (1–4) run/tested on this Windows machine. Swift/iOS-config tasks (5–8) are authored here but **compiled and verified on macOS (Xcode) or Codemagic** — they cannot be built on Windows.
- Preserve the existing `kForcePaywall` dev flag behavior (short-circuits Pro to false first).
- Follow existing patterns in `lib/features/subscription/windows_iap_service.dart` and `windows_iap_provider.dart`.

---

## File Structure

- Create: `lib/features/subscription/appcoins_iap_service.dart` — SKU const, status-mapping pure fn, `AppCoinsIapService` (channel calls).
- Create: `lib/features/subscription/appcoins_iap_provider.dart` — `AppCoinsIapNotifier`, `appCoinsIapProvider`, `appCoinsIsProProvider`.
- Modify: `lib/features/subscription/subscription_provider.dart` — iOS branch in `isProProvider`.
- Modify: `lib/features/subscription/presentation/paywall_screen.dart` — iOS branch in `showServePointPaywall` + `_AppCoinsPaywallDialog` (lifetime-only).
- Create: `ios/Runner/AppCoinsIapPlugin.swift` — native plugin wrapping AppCoinsSDK.
- Modify: `ios/Runner/AppDelegate.swift` — register plugin, `AppcSDK.initialize()`, deep-link handle, unfinished-purchase drain.
- Modify: `ios/Runner/SceneDelegate.swift` — `AppcSDK.initialize()` + redirect handling in scene entry points.
- Modify: `ios/Runner/Info.plist` — URL scheme + `MKSellsDigitalGoods`.
- Xcode project: add SwiftPM dependency + Keychain Sharing capability (Xcode UI on macOS).
- Create test: `test/features/subscription/appcoins_iap_service_test.dart`.

---

### Task 1: AppCoins SKU + purchase-status mapping (pure, TDD)

**Files:**
- Create: `lib/features/subscription/appcoins_iap_service.dart`
- Test: `test/features/subscription/appcoins_iap_service_test.dart`

**Interfaces:**
- Produces: `const kAppCoinsLifetimeSku` (String); `String? mapAppCoinsPurchaseStatus(String? status)` — returns `null` for success/cancel/pending, else a user-facing error message.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/subscription/appcoins_iap_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:servepoint/features/subscription/appcoins_iap_service.dart';

void main() {
  group('mapAppCoinsPurchaseStatus', () {
    test('success statuses return null (no error)', () {
      expect(mapAppCoinsPurchaseStatus('purchased'), isNull);
      expect(mapAppCoinsPurchaseStatus('alreadyPurchased'), isNull);
    });

    test('cancel and pending return null (no error)', () {
      expect(mapAppCoinsPurchaseStatus('cancelled'), isNull);
      expect(mapAppCoinsPurchaseStatus('pending'), isNull);
    });

    test('network error returns a connection message', () {
      expect(mapAppCoinsPurchaseStatus('networkError'),
          contains('connection'));
    });

    test('notAvailable returns an availability message', () {
      expect(mapAppCoinsPurchaseStatus('notAvailable'),
          contains("aren't available"));
    });

    test('unknown status is echoed in the message', () {
      expect(mapAppCoinsPurchaseStatus('weird'), contains('weird'));
    });
  });

  test('kAppCoinsLifetimeSku is the agreed SKU', () {
    expect(kAppCoinsLifetimeSku, 'servepoint_pro_lifetime');
  });
}
```

> Note: replace `servepoint` in the import with the package name from `pubspec.yaml` `name:` if different (the project's `.iml` files reference `servepoint`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/subscription/appcoins_iap_service_test.dart`
Expected: FAIL — `appcoins_iap_service.dart` / `mapAppCoinsPurchaseStatus` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/subscription/appcoins_iap_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// AppCoins SKU for the one-time lifetime Pro unlock on the iOS (Aptoide)
/// build. Must match the product SKU created in Aptoide Connect.
const kAppCoinsLifetimeSku = 'servepoint_pro_lifetime';

/// Maps a native purchase status string to a user-facing error message, or
/// null when no error should be shown (success / cancellation / pending).
String? mapAppCoinsPurchaseStatus(String? status) {
  switch (status) {
    case 'purchased':
    case 'alreadyPurchased':
    case 'cancelled':
    case 'pending':
      return null;
    case 'networkError':
      return 'Network error. Please check your connection and try again.';
    case 'serverError':
      return 'AppCoins server error. Please try again later.';
    case 'notAvailable':
      return "Pro purchases aren't available on this device.";
    default:
      return 'Purchase did not complete ($status).';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/subscription/appcoins_iap_service_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/subscription/appcoins_iap_service.dart test/features/subscription/appcoins_iap_service_test.dart
git commit -m "feat(ios-iap): add AppCoins SKU const and purchase-status mapping"
```

---

### Task 2: AppCoinsIapService channel methods

**Files:**
- Modify: `lib/features/subscription/appcoins_iap_service.dart`

**Interfaces:**
- Consumes: `kAppCoinsLifetimeSku`, `mapAppCoinsPurchaseStatus` (Task 1).
- Produces: `class AppCoinsIapService` with `static bool get isSupported`; `bool get isPro`; `bool get isStoreAvailable`; `Future<void> initialize()`; `Future<String?> fetchLifetimePriceString()`; `Future<String?> buyLifetime()`; `Future<bool> restore()`. Channel: `MethodChannel('com.servepoint/appcoins_iap')` with methods `isAvailable`, `checkLicense` (arg `sku`), `getPriceString` (arg `sku`), `purchase` (arg `sku`).

- [ ] **Step 1: Append the service class**

Add to the end of `lib/features/subscription/appcoins_iap_service.dart`:

```dart
/// Microsoft-Store-style wrapper around the native AppCoins SDK plugin.
/// Never does anything off iOS — all entry points guard on [isSupported].
class AppCoinsIapService {
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  static const _channel = MethodChannel('com.servepoint/appcoins_iap');

  bool _isPro = false;
  bool get isPro => _isPro;

  bool _storeAvailable = false;
  bool get isStoreAvailable => _storeAvailable;

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      _storeAvailable =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
      if (!_storeAvailable) {
        debugPrint('[AppCoins] SDK unavailable (non-EU / iOS<17.4 / '
            'App Store install).');
        return;
      }
      _isPro = await _checkLicense();
      debugPrint('[AppCoins] Initialized. isPro=$_isPro');
    } catch (e) {
      debugPrint('[AppCoins] initialize error: $e');
    }
  }

  Future<bool> _checkLicense() async {
    try {
      return await _channel.invokeMethod<bool>(
              'checkLicense', {'sku': kAppCoinsLifetimeSku}) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[AppCoins] checkLicense error: ${e.message}');
      return false;
    }
  }

  /// Live formatted price for the lifetime SKU, or null when unavailable
  /// (paywall falls back to the hardcoded display price).
  Future<String?> fetchLifetimePriceString() async {
    if (!isSupported || !_storeAvailable) return null;
    try {
      return await _channel.invokeMethod<String?>(
          'getPriceString', {'sku': kAppCoinsLifetimeSku});
    } catch (e) {
      debugPrint('[AppCoins] fetchLifetimePriceString error: $e');
      return null;
    }
  }

  /// Starts the AppCoins purchase flow for the lifetime SKU.
  /// Returns null on success/cancellation, or an error message on failure.
  Future<String?> buyLifetime() async {
    if (!isSupported) return null;
    if (!_storeAvailable) return mapAppCoinsPurchaseStatus('notAvailable');
    try {
      final status = await _channel
          .invokeMethod<String>('purchase', {'sku': kAppCoinsLifetimeSku});
      if (status == 'purchased' || status == 'alreadyPurchased') {
        _isPro = true;
      }
      return mapAppCoinsPurchaseStatus(status);
    } on PlatformException catch (e) {
      debugPrint('[AppCoins] buyLifetime error: ${e.message}');
      return e.message ?? 'Unknown AppCoins error.';
    } catch (e) {
      debugPrint('[AppCoins] buyLifetime error: $e');
      return e.toString();
    }
  }

  /// Re-checks ownership to restore a previous lifetime purchase.
  Future<bool> restore() async {
    if (!isSupported) return false;
    _isPro = await _checkLicense();
    return _isPro;
  }
}
```

- [ ] **Step 2: Verify it compiles / analyzes clean**

Run: `flutter analyze lib/features/subscription/appcoins_iap_service.dart`
Expected: No issues. (The service methods are exercised on-device; the host-side `isSupported` guard returns false off-iOS, so they no-op in unit tests — which is why Task 1's pure function carries the unit coverage.)

- [ ] **Step 3: Run the existing suite to confirm no regressions**

Run: `flutter test test/features/subscription/appcoins_iap_service_test.dart`
Expected: PASS (Task 1 tests still green).

- [ ] **Step 4: Commit**

```bash
git add lib/features/subscription/appcoins_iap_service.dart
git commit -m "feat(ios-iap): add AppCoinsIapService channel wrapper"
```

---

### Task 3: AppCoins providers + isProProvider iOS wiring

**Files:**
- Create: `lib/features/subscription/appcoins_iap_provider.dart`
- Modify: `lib/features/subscription/subscription_provider.dart`
- Test: `test/features/subscription/appcoins_iap_service_test.dart` (extend)

**Interfaces:**
- Consumes: `AppCoinsIapService` (Task 2).
- Produces: `appCoinsIapProvider` (`AsyncNotifierProvider<AppCoinsIapNotifier, bool>`); `appCoinsIsProProvider` (`Provider<bool>`); `AppCoinsIapNotifier` with `purchaseLifetime()`, `restore()`, `silentRestore()`, `AppCoinsIapService? get service`.

- [ ] **Step 1: Write the failing test (provider is false off-iOS host)**

Append to `test/features/subscription/appcoins_iap_service_test.dart`:

```dart
// add imports at top of file:
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:servepoint/features/subscription/appcoins_iap_provider.dart';

  test('appCoinsIsProProvider is false on non-iOS host', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appCoinsIsProProvider), isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/subscription/appcoins_iap_service_test.dart`
Expected: FAIL — `appcoins_iap_provider.dart` / `appCoinsIsProProvider` not found.

- [ ] **Step 3: Create the provider file**

```dart
// lib/features/subscription/appcoins_iap_provider.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appcoins_iap_service.dart';

class AppCoinsIapNotifier extends AsyncNotifier<bool> {
  AppCoinsIapService? _service;

  @override
  Future<bool> build() async {
    if (kIsWeb || !Platform.isIOS) return false;
    final service = AppCoinsIapService();
    _service = service;
    await service.initialize();
    return service.isPro;
  }

  /// Open the AppCoins lifetime purchase flow and wait for the result.
  Future<void> purchaseLifetime() async {
    final service = _service;
    if (service == null) return;
    state = const AsyncValue.loading();
    try {
      await service.buyLifetime();
    } finally {
      state = AsyncValue.data(service.isPro);
    }
  }

  /// Restore an existing lifetime purchase (shows loading state).
  Future<void> restore() async {
    state = const AsyncValue.loading();
    try {
      await _service?.restore();
    } finally {
      state = AsyncValue.data(_service?.isPro ?? false);
    }
  }

  /// Restore without flashing loading state (used from inside the paywall).
  Future<void> silentRestore() async {
    try {
      await _service?.restore();
      state = AsyncValue.data(_service?.isPro ?? false);
    } catch (_) {
      state = AsyncValue.data(_service?.isPro ?? false);
    }
  }

  AppCoinsIapService? get service => _service;
}

/// Provides the AppCoins IAP state (true = Pro active). Always false off iOS.
final appCoinsIapProvider =
    AsyncNotifierProvider<AppCoinsIapNotifier, bool>(AppCoinsIapNotifier.new);

/// Convenience bool — true when the iOS user owns the lifetime unlock.
final appCoinsIsProProvider = Provider<bool>((ref) {
  if (kIsWeb || !Platform.isIOS) return false;
  return ref.watch(appCoinsIapProvider).valueOrNull ?? false;
});
```

- [ ] **Step 4: Wire `isProProvider` (iOS branch)**

In `lib/features/subscription/subscription_provider.dart`, add the import near the other subscription imports:

```dart
import 'appcoins_iap_provider.dart';
```

Then change `isProProvider` so the body reads:

```dart
final isProProvider = Provider<bool>((ref) {
  if (kForcePaywall) return false;
  if (!kIsWeb && Platform.isWindows) {
    return ref.watch(windowsIsProProvider);
  }
  if (!kIsWeb && Platform.isIOS) {
    return ref.watch(appCoinsIsProProvider);
  }
  final infoAsync = ref.watch(subscriptionProvider);
  return infoAsync.when(
    data: hasProAccess,
    loading: () => false,
    error: (_, __) => false,
  );
});
```

- [ ] **Step 5: Run tests to verify pass**

Run: `flutter test test/features/subscription/appcoins_iap_service_test.dart`
Expected: PASS (all prior tests + the new provider test).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/subscription/`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/subscription/appcoins_iap_provider.dart lib/features/subscription/subscription_provider.dart test/features/subscription/appcoins_iap_service_test.dart
git commit -m "feat(ios-iap): add AppCoins providers and route isProProvider on iOS"
```

---

### Task 4: iOS paywall dialog (lifetime-only)

**Files:**
- Modify: `lib/features/subscription/presentation/paywall_screen.dart`

**Interfaces:**
- Consumes: `appCoinsIapProvider`, `appCoinsIsProProvider` (Task 3); existing `_PaywallCard`, `AppColors`.
- Produces: iOS branch in `showServePointPaywall`; `_AppCoinsPaywallDialog` widget.

- [ ] **Step 1: Add the iOS branch in `showServePointPaywall`**

In `paywall_screen.dart`, add this immediately after the Windows branch (after the block ending `return ref.read(windowsIsProProvider);` near line 31), before `if (!isRevenueCatSupported)`:

```dart
  // ── iOS: Aptoide AppCoins IAP ────────────────────────────────────────────
  if (!kIsWeb && Platform.isIOS) {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AppCoinsPaywallDialog(),
    );
    return ref.read(appCoinsIsProProvider);
  }
```

Add the import at the top of the file (near the other subscription imports):

```dart
import '../appcoins_iap_provider.dart';
```

- [ ] **Step 2: Add the `_AppCoinsPaywallDialog` widget**

Add after the `_WindowsPaywallDialog` state class (after its closing brace, before `_UnsupportedPlatformDialog`):

```dart
// ─── iOS AppCoins Paywall (lifetime only) ─────────────────────────────────────

class _AppCoinsPaywallDialog extends ConsumerStatefulWidget {
  const _AppCoinsPaywallDialog();

  @override
  ConsumerState<_AppCoinsPaywallDialog> createState() =>
      _AppCoinsPaywallDialogState();
}

class _AppCoinsPaywallDialogState
    extends ConsumerState<_AppCoinsPaywallDialog> {
  String? _priceString;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = ref.read(appCoinsIapProvider.notifier).service;
      if (service == null) return;
      final price = await service.fetchLifetimePriceString();
      if (!mounted) return;
      setState(() => _priceString = _usablePrice(price));
    });
  }

  Future<void> _buy() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(appCoinsIapProvider.notifier).purchaseLifetime();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    await ref.read(appCoinsIapProvider.notifier).silentRestore();
    if (!mounted) return;
    if (ref.read(appCoinsIsProProvider)) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous purchase found.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(appCoinsIsProProvider, (_, isPro) {
      if (isPro && mounted) Navigator.pop(context);
    });

    return AlertDialog(
      backgroundColor: AppColors.headerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.workspace_premium_rounded,
            color: AppColors.accentAmber, size: 22),
        SizedBox(width: 8),
        Text('ServePoint Pro',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _PaywallCard(
              title: 'Lifetime',
              price: _priceString ?? '\$99',
              period: 'one-time',
              bullets: const [
                'Pay once, own forever',
                'No subscription, no renewals',
                'All Pro features',
              ],
              ctaLabel: 'Get lifetime',
              loading: _loading,
              onPressed: _buy,
              highlighted: true,
              badge: 'Best value',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _restore,
                child: const Text('Restore purchase',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}
```

> `_usablePrice` and `_PaywallCard` already exist in this file (used by the Windows dialog) — reuse them, do not redefine.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/subscription/presentation/paywall_screen.dart`
Expected: No issues.

- [ ] **Step 4: Run full Dart test suite**

Run: `flutter test`
Expected: PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add lib/features/subscription/presentation/paywall_screen.dart
git commit -m "feat(ios-iap): add AppCoins lifetime paywall dialog on iOS"
```

---

### Task 5: AppCoins native plugin (Swift) — macOS/Xcode

**Files:**
- Create: `ios/Runner/AppCoinsIapPlugin.swift`

**Interfaces:**
- Produces: `class AppCoinsIapPlugin: NSObject, FlutterPlugin` registered on channel `com.servepoint/appcoins_iap`, handling `isAvailable`, `getPriceString`, `purchase`, `checkLicense`. Returns purchase status strings matching `mapAppCoinsPurchaseStatus`: `purchased`, `alreadyPurchased`, `cancelled`, `pending`, `networkError`, `serverError`, `notAvailable`, `unknown`.

- [ ] **Step 1: Create the plugin file**

```swift
// ios/Runner/AppCoinsIapPlugin.swift
import Flutter
import UIKit
import AppCoinsSDK

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
      // Lifetime (non-consumable) is owned when its latest purchase exists
      // and is not consumed.
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
```

> **VERIFY during build (SDK-detail items the docs were thin on):**
> 1. `purchase.state` representation — the code stringifies it (`"\(purchase.state)"`) and compares to `"CONSUMED"`; adjust to the real enum (e.g. `.consumed`) once the SDK type is visible in Xcode.
> 2. `AppCoinsSDKError` case names in the `switch` — confirm `.networkError` exists; keep `default` catch-all.
> 3. Confirm `finish()` acknowledges (not consumes) a non-consumable. If a separate acknowledge API exists, use it.

- [ ] **Step 2: Verify (macOS/Xcode)**

This task compiles only after Task 6/7 add the SwiftPM dependency and config. Defer build verification to Task 8. Mark this task's box once the file is written; it is verified by the Task 8 build.

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/AppCoinsIapPlugin.swift
git commit -m "feat(ios-iap): add AppCoinsIapPlugin native channel handler"
```

---

### Task 6: iOS project config — SwiftPM, capabilities, Info.plist — macOS/Xcode

**Files:**
- Modify: `ios/Runner/Info.plist`
- Xcode project (via Xcode UI on macOS): SwiftPM dependency + Keychain Sharing capability.

**Interfaces:**
- Produces: AppCoinsSDK linked; URL scheme `$(PRODUCT_BUNDLE_IDENTIFIER).iap`; `MKSellsDigitalGoods=YES`; Keychain group `com.aptoide.appcoins-wallet`.

- [ ] **Step 1: Add the SwiftPM dependency (Xcode)**

In Xcode: open `ios/Runner.xcworkspace` → select the **Runner** project → **Package Dependencies** tab → **+** → enter `https://github.com/Catappult/appcoins-sdk-ios.git` → add the `AppCoinsSDK` library product to the **Runner** target.

- [ ] **Step 2: Add Keychain Sharing capability (Xcode)**

Runner target → **Signing & Capabilities** → **+ Capability** → **Keychain Sharing** → add a Keychain Group with value `com.aptoide.appcoins-wallet`. (This creates/updates `ios/Runner/Runner.entitlements` with `keychain-access-groups`.)

- [ ] **Step 3: Add URL scheme + digital-goods key to Info.plist**

Edit `ios/Runner/Info.plist`. Add inside the top-level `<dict>`:

```xml
	<key>MKSellsDigitalGoods</key>
	<true/>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>$(PRODUCT_BUNDLE_IDENTIFIER).iap</string>
			</array>
		</dict>
	</array>
```

> If `CFBundleURLTypes` already exists, append the new `<dict>` to its `<array>` instead of adding a second key.

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj ios/Runner/Runner.entitlements
git commit -m "build(ios-iap): add AppCoinsSDK dependency, keychain group, URL scheme"
```

---

### Task 7: App/Scene delegate integration — macOS/Xcode

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/Runner/SceneDelegate.swift`

**Interfaces:**
- Consumes: `AppCoinsIapPlugin` (Task 5).
- Produces: plugin registered on the implicit engine; `AppcSDK.initialize()` + `AppcSDK.handle(redirectURL:)` in entry points; unfinished-purchase drain on launch.

- [ ] **Step 1: Update AppDelegate**

Replace `ios/Runner/AppDelegate.swift` with:

```swift
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

  private func drainUnfinishedPurchases() {
    Task {
      guard await AppcSDK.isAvailable() else { return }
      if let purchases = try? await Purchase.unfinished() {
        for purchase in purchases { try? await purchase.finish() }
      }
    }
  }
}
```

- [ ] **Step 2: Update SceneDelegate**

Replace `ios/Runner/SceneDelegate.swift` with:

```swift
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
```

> **VERIFY during build:** confirm `FlutterSceneDelegate` exposes overridable `scene(_:willConnectTo:options:)` and `scene(_:openURLContexts:)` in your Flutter version; if it does not, move the `AppcSDK.handle` calls entirely into `AppDelegate`'s `open url` method (which already covers redirects).

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/AppDelegate.swift ios/Runner/SceneDelegate.swift
git commit -m "feat(ios-iap): init AppCoins SDK, register plugin, drain unfinished purchases"
```

---

### Task 8: Build, integration verification & test config — macOS/Codemagic

**Files:** none (verification).

- [ ] **Step 1: Build the iOS app**

On macOS: `flutter build ios --release --no-codesign` (or via Codemagic using `codemagic.yaml`).
Expected: Builds clean. Fix any SDK-detail mismatches flagged in Tasks 5 & 7 (`purchase.state` enum, `AppCoinsSDKError` cases, scene override signatures).

- [ ] **Step 2: Configure AppCoins test mode (Xcode)**

Runner target Build Settings → set **Marketplaces** to `com.aptoide.ios.store`. Edit Scheme → **Run** → set Distribution to `com.aptoide.ios.store`.

- [ ] **Step 3: Manual device verification (EU device or test config, iOS 17.4+)**

Verify in order:
1. Paywall shows the lifetime card with the live price (or `$99` fallback).
2. Tapping **Get lifetime** opens the AppCoins/Aptoide wallet purchase flow.
3. After purchase, the dialog auto-closes and Pro features unlock (`isProProvider` true).
4. Relaunch the app → still Pro (`checkLicense` persists ownership).
5. Kill the app mid-purchase, relaunch → the unfinished-purchase drain finalizes it.
6. On a non-EU/simulator build, paywall purchase surfaces "aren't available on this device" and `--dart-define=FORCE_PAYWALL=true` still forces the paywall for UI checks.

- [ ] **Step 4: Final commit (if any fixes were applied)**

```bash
git add -A
git commit -m "fix(ios-iap): resolve AppCoins SDK build/runtime details"
```

---

## Addendum (2026-06-19): Codemagic-script wiring supersedes Task 6 Xcode-UI steps

Because the project is configured on Windows (no Xcode), the SwiftPM dependency,
keychain capability, and 17.4 deployment-target bump are NOT committed as
project.pbxproj edits. Instead they are injected on the Codemagic macOS builder
before `flutter build ipa` by `ios/scripts/add_appcoins_spm.rb` (idempotent,
edits the ephemeral CI checkout only), invoked from a new `codemagic.yaml` step
"Inject AppCoins SDK (SwiftPM) + entitlements". The Info.plist edits and
`Runner/Runner.entitlements` ARE committed (plain text, safe on Windows).
SDK pinned to `>= 4.3.2 < 5.0.0`. Verification = the Codemagic build (Task 8).

## Self-Review

**Spec coverage:**
- Aptoide-only / AppCoins sole billing → Tasks 5–8. ✔
- One-time lifetime non-consumable → Task 5 (`finish` not consume), Task 1 SKU. ✔
- $99 price + live `priceLabel` + fallback → Task 2 `fetchLifetimePriceString`, Task 4 `$99` fallback. ✔
- Approach A native channel mirroring Windows → Tasks 2/3/5. ✔
- Channel `com.servepoint/appcoins_iap` → Tasks 2 & 5 (match). ✔
- iOS config (SwiftPM, keychain group, URL scheme, MKSellsDigitalGoods) → Task 6. ✔
- `AppcSDK.initialize()` + `handle()` in Scene/AppDelegate + unfinished drain → Task 7. ✔
- `isProProvider` iOS branch, `kForcePaywall` preserved → Task 3 Step 4. ✔
- Availability fallback (not-Pro + message) → Task 2 `buyLifetime` notAvailable, Task 1 message. ✔
- Error mapping from `AppCoinsSDKError` → Task 5 `mapError`, Task 1 mapping. ✔
- Testing config (`com.aptoide.ios.store`, FORCE_PAYWALL) → Task 8. ✔
- Open item: `finish()` acknowledge-vs-consume + `purchase.state` enum → flagged in Task 5/7 VERIFY notes. ✔

**Placeholder scan:** No TBD/TODO. The "VERIFY during build" notes are concrete build-time checks against the live SDK types, not deferred work.

**Type consistency:** Status strings produced by Task 5 (`purchased`, `alreadyPurchased`, `cancelled`, `pending`, `networkError`, `serverError`, `notAvailable`, `unknown`) all map in Task 1's `mapAppCoinsPurchaseStatus`. Channel name, method names (`isAvailable`/`getPriceString`/`purchase`/`checkLicense`) and `sku` arg match across Dart (Task 2) and Swift (Task 5). Provider/notifier names (`appCoinsIapProvider`, `appCoinsIsProProvider`, `purchaseLifetime`, `silentRestore`, `service`) consistent across Tasks 3 & 4.
