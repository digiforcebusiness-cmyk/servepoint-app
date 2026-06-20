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
