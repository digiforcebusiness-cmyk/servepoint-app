import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'subscription_service.dart';
import 'windows_iap_provider.dart';

// ─── CustomerInfo state ───────────────────────────────────────────────────────

class SubscriptionNotifier extends AsyncNotifier<CustomerInfo?> {
  @override
  Future<CustomerInfo?> build() async {
    if (!isRevenueCatSupported) return null;

    // Listen for real-time CustomerInfo updates from RevenueCat.
    Purchases.addCustomerInfoUpdateListener((info) {
      state = AsyncValue.data(info);
    });

    return fetchCustomerInfo();
  }

  /// Manually refresh — useful after a deep-link or promotional grant.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await fetchCustomerInfo());
  }

  /// Restore purchases (cross-device).
  Future<bool> restore() async {
    state = const AsyncValue.loading();
    final info = await restorePurchases();
    state = AsyncValue.data(info);
    return hasProAccess(info);
  }
}

/// Provides the current [CustomerInfo] (null on unsupported platforms).
final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, CustomerInfo?>(
  SubscriptionNotifier.new,
);

/// Convenience provider — true when the user has an active Pro entitlement.
/// Windows: uses Microsoft Store IAP via [windowsIsProProvider].
/// Android / iOS / macOS: uses RevenueCat.
final isProProvider = Provider<bool>((ref) {
  if (!kIsWeb && Platform.isWindows) {
    return ref.watch(windowsIsProProvider);
  }
  final infoAsync = ref.watch(subscriptionProvider);
  return infoAsync.when(
    data: hasProAccess,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// Expiry date of the active Pro entitlement (null if not subscribed or unsupported).
final proExpiryProvider = Provider<DateTime?>((ref) {
  if (!isRevenueCatSupported) return null;
  final info = ref.watch(subscriptionProvider).valueOrNull;
  final entitlement = info?.entitlements.active[kProEntitlement];
  if (entitlement?.expirationDate == null) return null;
  return DateTime.tryParse(entitlement!.expirationDate!);
});
