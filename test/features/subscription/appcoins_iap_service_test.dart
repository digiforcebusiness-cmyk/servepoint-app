// test/features/subscription/appcoins_iap_service_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servepoint/features/subscription/appcoins_iap_provider.dart';
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

  test('appCoinsIsProProvider is false on non-iOS host', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appCoinsIsProProvider), isFalse);
  });
}
