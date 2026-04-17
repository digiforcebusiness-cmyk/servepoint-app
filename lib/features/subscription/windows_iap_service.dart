import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// The Microsoft Store Add-on Store ID for ServePoint Pro.
/// This is the auto-generated Store ID from Partner Center → Add-ons → servepoint_pro_monthly.
const kWindowsProProductId = '9NP8JK6X73SJ';

/// Handles Microsoft Store In-App Purchases on Windows only.
/// Never instantiated or called on Android / iOS — all entry points are
/// guarded by [WindowsIAPService.isSupported].
class WindowsIAPService {
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _isPro = false;
  bool get isPro => _isPro;

  final _proController = StreamController<bool>.broadcast();

  /// Emits whenever Pro status changes (purchase or restore confirmed).
  Stream<bool> get proStream => _proController.stream;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!isSupported) return;
    if (!await _iap.isAvailable()) {
      debugPrint('[WindowsIAP] Microsoft Store not available on this device.');
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => debugPrint('[WindowsIAP] Stream error: $e'),
    );

    // Silently restore on start-up so returning subscribers are recognised.
    await _iap.restorePurchases();
  }

  void dispose() {
    _purchaseSub?.cancel();
    _proController.close();
  }

  // ─── Purchase stream handler ────────────────────────────────────────────────

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID != kWindowsProProductId) continue;

      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _isPro = true;
          _proController.add(true);
          if (p.pendingCompletePurchase) _iap.completePurchase(p);
        case PurchaseStatus.error:
          debugPrint('[WindowsIAP] Purchase error: ${p.error}');
        case PurchaseStatus.canceled:
          debugPrint('[WindowsIAP] Purchase cancelled by user.');
        case PurchaseStatus.pending:
          debugPrint('[WindowsIAP] Purchase pending.');
      }
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Fetches product details from the Microsoft Store.
  Future<ProductDetails?> fetchProProduct() async {
    if (!isSupported) return null;
    final response =
        await _iap.queryProductDetails({kWindowsProProductId});
    if (response.error != null) {
      debugPrint('[WindowsIAP] queryProductDetails error: ${response.error}');
    }
    return response.productDetails.firstOrNull;
  }

  /// Initiates the Microsoft Store subscription purchase flow.
  Future<void> buyPro() async {
    if (!isSupported) return;
    final product = await fetchProProduct();
    if (product == null) {
      debugPrint('[WindowsIAP] Product not found in Store — '
          'make sure the Add-on is published in Partner Center.');
      return;
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Restores previously purchased subscriptions.
  Future<void> restore() async {
    if (!isSupported) return;
    await _iap.restorePurchases();
  }
}
