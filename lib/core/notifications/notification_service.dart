import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/app_database.dart';

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _lowStockChannelId = 'low_stock';
  static const _dailySummaryChannelId = 'daily_summary';

  static Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);

    // Request permission on Android 13+
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    // Request permission on iOS
    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  /// Show an immediate low-stock alert for a single ingredient.
  static Future<void> showLowStockAlert(String ingredientName) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        ingredientName.hashCode,
        '⚠️ Stock faible',
        '$ingredientName est en dessous du seuil minimum',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _lowStockChannelId,
            'Alertes stock faible',
            channelDescription:
                'Notifications quand un ingrédient est en rupture',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Notifications] showLowStockAlert error: $e');
    }
  }

  /// Show a daily summary notification listing low-stock ingredients.
  static Future<void> showDailySummary(List<Ingredient> lowItems) async {
    if (!_initialized || lowItems.isEmpty) return;
    try {
      final names = lowItems.map((i) => i.name).join(', ');
      await _plugin.show(
        999,
        '📋 Résumé stock — ${lowItems.length} article(s) à réapprovisionner',
        names,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _dailySummaryChannelId,
            'Résumé quotidien',
            channelDescription: 'Résumé de fin de journée des stocks faibles',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(
              'Articles à commander : $names',
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Notifications] showDailySummary error: $e');
    }
  }
}
