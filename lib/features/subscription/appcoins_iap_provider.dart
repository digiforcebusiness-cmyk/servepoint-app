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
