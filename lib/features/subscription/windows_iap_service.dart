import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Microsoft Store Add-on Store ID for the ServePoint Pro monthly
/// subscription (`servepoint_pro_monthly_access`, $4.99/mo). Replaces the
/// earlier `9NP8JK6X73SJ` add-on, which could never be priced (Store offered
/// only "Free") and was abandoned.
const kWindowsProProductId = '9P7QBH6P9Q9F';

/// The Microsoft Store Add-on Store ID for the one-time lifetime unlock.
const kWindowsLifetimeProductId = '9P2DTR0674TK';

/// Handles Microsoft Store In-App Purchases on Windows only via a native
/// platform channel backed by WinRT Windows.Services.Store APIs.
/// Never instantiated or called on Android / iOS — all entry points are
/// guarded by [WindowsIAPService.isSupported].
class WindowsIAPService {
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  static const _channel = MethodChannel('com.servepoint/store_iap');

  bool _isPro = false;
  bool get isPro => _isPro;

  bool _storeAvailable = false;
  bool get isStoreAvailable => _storeAvailable;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      if (!available) {
        debugPrint('[WindowsIAP] Not running as MSIX package — IAP unavailable.');
        return;
      }
      _storeAvailable = true;
      _isPro = await _checkLicense();
      debugPrint('[WindowsIAP] Initialized. isPro=$_isPro');
    } catch (e) {
      debugPrint('[WindowsIAP] Initialize error: $e');
    }
  }

  void dispose() {}

  // ─── Internal helpers ───────────────────────────────────────────────────────

  Future<bool> _checkLicense() async {
    try {
      return await _channel.invokeMethod<bool>('checkLicense') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[WindowsIAP] checkLicense error: ${e.message}');
      return false;
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Returns the formatted price string from the Microsoft Store, or null if
  /// unavailable (paywall falls back to the hardcoded display price).
  Future<String?> fetchPriceString() async {
    if (!isSupported || !_storeAvailable) return null;
    try {
      final price = await _channel.invokeMethod<String?>('getPriceString', {
        'productId': kWindowsProProductId,
      });
      return price;
    } catch (e) {
      debugPrint('[WindowsIAP] fetchPriceString error: $e');
      return null;
    }
  }

  /// Same as [fetchPriceString] but for the lifetime durable add-on.
  Future<String?> fetchLifetimePriceString() async {
    if (!isSupported || !_storeAvailable) return null;
    try {
      final price = await _channel.invokeMethod<String?>('getPriceString', {
        'productId': kWindowsLifetimeProductId,
      });
      return price;
    } catch (e) {
      debugPrint('[WindowsIAP] fetchLifetimePriceString error: $e');
      return null;
    }
  }

  /// Initiates the Microsoft Store subscription purchase flow.
  /// Returns null on success or user cancellation; returns an error message
  /// on a hard failure.
  Future<String?> buyPro() async {
    if (!isSupported) return null;
    try {
      final status = await _channel.invokeMethod<String>('purchase', {
        'productId': kWindowsProProductId,
      });
      switch (status) {
        case 'purchased':
        case 'alreadyPurchased':
          _isPro = true;
          return null;
        case 'cancelled':
          return null;
        case 'networkError':
          return 'Network error. Please check your connection and try again.';
        case 'serverError':
          return 'Microsoft Store server error. Please try again later.';
        default:
          return 'Purchase did not complete ($status).';
      }
    } on PlatformException catch (e) {
      debugPrint('[WindowsIAP] buyPro error: ${e.message}');
      return e.message ?? 'Unknown Store error.';
    } catch (e) {
      debugPrint('[WindowsIAP] buyPro error: $e');
      return e.toString();
    }
  }

  /// Initiates the Microsoft Store one-time lifetime durable purchase flow.
  /// Returns null on success or user cancellation; returns an error message
  /// on a hard failure. On a successful purchase, [_isPro] flips to true —
  /// the native `checkLicense` already counts a lifetime durable as Pro, so
  /// no other state needs to change.
  Future<String?> buyLifetime() async {
    if (!isSupported) return null;
    try {
      final status = await _channel.invokeMethod<String>('purchase', {
        'productId': kWindowsLifetimeProductId,
      });
      switch (status) {
        case 'purchased':
        case 'alreadyPurchased':
          _isPro = true;
          return null;
        case 'cancelled':
          return null;
        case 'networkError':
          return 'Network error. Please check your connection and try again.';
        case 'serverError':
          return 'Microsoft Store server error. Please try again later.';
        default:
          return 'Purchase did not complete ($status).';
      }
    } on PlatformException catch (e) {
      debugPrint('[WindowsIAP] buyLifetime error: ${e.message}');
      return e.message ?? 'Unknown Store error.';
    } catch (e) {
      debugPrint('[WindowsIAP] buyLifetime error: $e');
      return e.toString();
    }
  }

  /// Re-checks the Microsoft Store license to restore a previously purchased
  /// subscription. Returns true when an active subscription was found.
  Future<bool> restore() async {
    if (!isSupported) return false;
    _isPro = await _checkLicense();
    return _isPro;
  }
}
