import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:foxcloud/common/print.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/plugins/vpn.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level function for handling background FCM messages.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages on Android are automatically shown by the system
  // if they have a 'notification' payload. Data-only messages can be
  // processed here if needed.
  print('[FCM] Background message: ${message.messageId}');
}

/// Service for Firebase Cloud Messaging push notifications.
/// Handles token registration, foreground message display, and permissions.
class FcmService {
  static const String _tag = '[FCM]';
  static const String _prefsKeyFcmToken = 'fcm_device_token';
  static const String _prefsKeyTokenSent = 'fcm_token_sent';

  static bool _initialized = false;

  /// Initialize FCM: request permissions, get token, register with server.
  /// Call this once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    _initialized = true;

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // Request notification permission (Android 13+ requires runtime permission)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    commonPrint.log('$_tag Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      commonPrint.log('$_tag User denied notification permission');
      return;
    }

    // Get FCM token
    try {
      final token = await messaging.getToken();
      if (token != null) {
        commonPrint.log('$_tag Token obtained (${token.length} chars)');
        await _registerTokenWithServer(token);
      }
    } catch (e) {
      commonPrint.log('$_tag Error getting token: $e');
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) {
      commonPrint.log('$_tag Token refreshed');
      _registerTokenWithServer(newToken);
    });

    // Handle foreground messages — show via native notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      commonPrint.log('$_tag Foreground message: ${message.notification?.title}');
      final notification = message.notification;
      if (notification != null) {
        _showLocalNotification(
          title: notification.title ?? '',
          body: notification.body ?? '',
        );
      }
    });

    // Handle notification tap (app opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      commonPrint.log('$_tag Notification tapped: ${message.data}');
      // Can handle deep links here in the future
    });
  }

  /// Register FCM token with the server so it can send pushes to this device.
  static Future<void> _registerTokenWithServer(String fcmToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final subUrl = prefs.getString(FoxConfig.keySubscriptionUrl);

      if (subUrl == null || subUrl.isEmpty) {
        commonPrint.log('$_tag No subscription URL, saving token for later');
        await prefs.setString(_prefsKeyFcmToken, fcmToken);
        await prefs.setBool(_prefsKeyTokenSent, false);
        return;
      }

      // Check if we already sent this exact token
      final savedToken = prefs.getString(_prefsKeyFcmToken);
      final alreadySent = prefs.getBool(_prefsKeyTokenSent) ?? false;
      if (savedToken == fcmToken && alreadySent) {
        commonPrint.log('$_tag Token already registered with server');
        return;
      }

      final baseUrl = _getBaseUrl();
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/mobile/fcm-register'),
        headers: {
          'Content-Type': 'application/json',
          'x-sub-url': subUrl,
        },
        body: json.encode({'fcm_token': fcmToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          commonPrint.log('$_tag Token registered with server');
          await prefs.setString(_prefsKeyFcmToken, fcmToken);
          await prefs.setBool(_prefsKeyTokenSent, true);
        }
      } else {
        commonPrint.log('$_tag Server responded with ${response.statusCode}');
      }
    } catch (e) {
      commonPrint.log('$_tag Error registering token: $e');
    }
  }

  /// Re-register token after user logs in (gets a subscription URL).
  /// Call this from the login flow.
  static Future<void> reRegisterToken() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefsKeyFcmToken);
      if (savedToken != null && savedToken.isNotEmpty) {
        await prefs.setBool(_prefsKeyTokenSent, false);
        await _registerTokenWithServer(savedToken);
      } else {
        // Try to get a fresh token
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _registerTokenWithServer(token);
        }
      }
    } catch (e) {
      commonPrint.log('$_tag Error re-registering: $e');
    }
  }

  /// Show a local notification via the native VPN plugin method channel.
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      await vpn?.showSubscriptionNotification(
        title: title,
        message: body,
        actionLabel: '',
        actionUrl: '',
      );
    } catch (e) {
      commonPrint.log('$_tag Error showing notification: $e');
    }
  }

  /// Get base URL from config.
  static String _getBaseUrl() {
    final authUrl = FoxConfig.authServerUrl;
    final idx = authUrl.indexOf('/api/');
    if (idx != -1) return authUrl.substring(0, idx);
    return authUrl;
  }
}
