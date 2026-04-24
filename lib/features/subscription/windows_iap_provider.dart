import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'windows_iap_service.dart';

// ─── Notifier ────────────────────────────────────────────────────────────────

class WindowsIAPNotifier extends AsyncNotifier<bool> {
  WindowsIAPService? _service;

  @override
  Future<bool> build() async {
    if (kIsWeb || !Platform.isWindows) return false;

    final service = WindowsIAPService();
    _service = service;

    // Update state whenever a purchase / restore is confirmed.
    service.proStream.listen((isPro) {
      state = AsyncValue.data(isPro);
    });

    ref.onDispose(service.dispose);
    await service.initialize();
    return service.isPro;
  }

  /// Open the Microsoft Store subscription purchase flow.
  Future<void> purchase() async => _service?.buyPro();

  /// Restore existing Microsoft Store purchases (shows loading state).
  Future<void> restore() async {
    state = const AsyncValue.loading();
    try {
      await _service?.restore();
      // Give the purchase stream a moment to emit before settling.
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      // Always settle the state — never leave the app stuck on loading.
      state = AsyncValue.data(_service?.isPro ?? false);
    }
  }

  /// Silently restore without setting loading state, so AppGate does not
  /// flash OnboardingScreen back to page 0. Used from within the paywall dialog.
  Future<void> silentRestore() async {
    try {
      await _service?.restore();
      await Future<void>.delayed(const Duration(seconds: 2));
      state = AsyncValue.data(_service?.isPro ?? false);
    } catch (_) {
      state = AsyncValue.data(_service?.isPro ?? false);
    }
  }

  /// Expose service so the UI can fetch the price string.
  WindowsIAPService? get service => _service;
}

/// Provides the Windows IAP state (true = Pro active).
/// Always returns false on non-Windows platforms.
final windowsIAPProvider =
    AsyncNotifierProvider<WindowsIAPNotifier, bool>(WindowsIAPNotifier.new);

/// Convenience bool — true when the Windows user has an active Pro subscription.
final windowsIsProProvider = Provider<bool>((ref) {
  if (kIsWeb || !Platform.isWindows) return false;
  return ref.watch(windowsIAPProvider).valueOrNull ?? false;
});
