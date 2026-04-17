import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The RevenueCat entitlement identifier configured in the dashboard.
const kProEntitlement = 'ServePoint Pro';

/// RevenueCat API keys — replace both with production keys from app.revenuecat.com before release.
/// Android key starts with 'goog_', iOS key starts with 'appl_'.
const _rcAndroidKey = 'goog_hvmwNMommvltYvhnAxPJTFSrCCS';
const _rcIosKey = 'appl_REPLACE_WITH_IOS_KEY_FROM_REVENUECAT'; // TODO: add iOS key

/// Returns true when the current platform supports RevenueCat (Android / iOS / macOS).
bool get isRevenueCatSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// Initialise RevenueCat.  Safe to call multiple times — skips on unsupported platforms.
Future<void> configureRevenueCat({String? appUserId}) async {
  if (!isRevenueCatSupported) return;

  await Purchases.setLogLevel(LogLevel.debug);
  final apiKey = Platform.isIOS || Platform.isMacOS ? _rcIosKey : _rcAndroidKey;
  final config = PurchasesConfiguration(apiKey);
  if (appUserId != null && appUserId.isNotEmpty) {
    config.appUserID = appUserId;
  }
  await Purchases.configure(config);
}

/// Fetch the current [CustomerInfo].
/// On unsupported platforms returns a synthetic "all-access" object.
Future<CustomerInfo?> fetchCustomerInfo() async {
  if (!isRevenueCatSupported) return null;
  try {
    return await Purchases.getCustomerInfo();
  } catch (e) {
    debugPrint('[RevenueCat] fetchCustomerInfo error: $e');
    return null;
  }
}

/// Returns true if the customer has an active *ServePoint Pro* entitlement.
bool hasProAccess(CustomerInfo? info) {
  if (!isRevenueCatSupported) return true; // Windows / unsupported → unlock Pro
  if (info == null) return false;
  return info.entitlements.active.containsKey(kProEntitlement);
}

/// Restore purchases and return updated [CustomerInfo].
Future<CustomerInfo?> restorePurchases() async {
  if (!isRevenueCatSupported) return null;
  try {
    return await Purchases.restorePurchases();
  } catch (e) {
    debugPrint('[RevenueCat] restorePurchases error: $e');
    return null;
  }
}

/// Log the current user out (anonymous → new anonymous ID).
Future<CustomerInfo?> logOut() async {
  if (!isRevenueCatSupported) return null;
  try {
    return await Purchases.logOut();
  } catch (e) {
    debugPrint('[RevenueCat] logOut error: $e');
    return null;
  }
}
