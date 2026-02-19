import 'dart:io';

import 'package:foxcloud/common/print.dart';
import 'package:foxcloud/plugins/vpn.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for polling server push notifications and showing them
/// in the phone's notification shade via the native VPN plugin.
class PushNotificationService {
  static const String _prefsKeyLastId = 'push_notification_last_id';

  /// Check for new push notifications from the server and display them.
  static Future<void> checkAndShow() async {
    if (!Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getInt(_prefsKeyLastId) ?? 0;

      commonPrint.log('[PushNotification] Checking for notifications after id=$lastId');

      final notifications =
          await PurchaseService.instance.fetchNewNotifications(lastId);

      if (notifications.isEmpty) {
        commonPrint.log('[PushNotification] No new notifications');
        return;
      }

      commonPrint.log('[PushNotification] Got ${notifications.length} new notification(s)');

      // Show each notification in the shade
      for (final notif in notifications) {
        await vpn?.showSubscriptionNotification(
          title: notif.title,
          message: notif.message,
          actionLabel: '',
          actionUrl: '',
        );
      }

      // Save the highest seen id
      final maxId = notifications.map((n) => n.id).reduce((a, b) => a > b ? a : b);
      await prefs.setInt(_prefsKeyLastId, maxId);
      commonPrint.log('[PushNotification] Updated last id to $maxId');
    } catch (e) {
      commonPrint.log('[PushNotification] Error: $e');
    }
  }
}
