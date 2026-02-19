import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a Telegram auth flow.
class TelegramAuthResult {
  final bool success;
  final String? subscriptionUrl;
  final String? telegramId;
  final String? username;
  final String? firstName;
  final String? photoUrl;
  final String? error;

  TelegramAuthResult({
    required this.success,
    this.subscriptionUrl,
    this.telegramId,
    this.username,
    this.firstName,
    this.photoUrl,
    this.error,
  });
}

/// Service that handles Telegram-based authentication.
///
/// Flow:
/// 1. Generate a random auth token
/// 2. Open Telegram bot with deep link ?start=auth_{token}
/// 3. Poll auth server every 2 seconds until bot confirms OR timeout
/// 4. On success, save user data + subscription URL
class TelegramAuthService {
  TelegramAuthService._();
  static final instance = TelegramAuthService._();

  Timer? _pollTimer;
  Completer<TelegramAuthResult>? _authCompleter;
  int _pollAttempts = 0;
  String? _currentToken;

  bool get isPolling => _pollTimer?.isActive ?? false;

  /// Generate a unique auth token.
  String _generateAuthToken() {
    final raw =
        '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  /// Start the full Telegram auth flow.
  ///
  /// Opens Telegram, starts polling, and returns the result as a Future.
  Future<TelegramAuthResult> startAuth() async {
    cancel();

    _currentToken = _generateAuthToken();
    _pollAttempts = 0;
    _authCompleter = Completer<TelegramAuthResult>();

    // Open Telegram deep link
    final telegramUrl = Uri.parse(
      'https://t.me/${FoxConfig.telegramBotUsername}?start=auth_$_currentToken',
    );

    try {
      await launchUrl(telegramUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      return TelegramAuthResult(
        success: false,
        error: 'Не удалось открыть Telegram: $e',
      );
    }

    // Start polling
    final maxAttempts =
        FoxConfig.authTimeout.inSeconds ~/ FoxConfig.authPollInterval.inSeconds;

    _pollTimer = Timer.periodic(FoxConfig.authPollInterval, (timer) async {
      _pollAttempts++;

      if (_pollAttempts >= maxAttempts) {
        timer.cancel();
        if (!_authCompleter!.isCompleted) {
          _authCompleter!.complete(TelegramAuthResult(
            success: false,
            error: 'Время ожидания истекло. Попробуйте снова.',
          ));
        }
        return;
      }

      try {
        final response = await http.get(
          Uri.parse(
              '${FoxConfig.authServerUrl}/check?token=$_currentToken'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            timer.cancel();

            final result = TelegramAuthResult(
              success: true,
              subscriptionUrl: data['subscription_url']?.toString(),
              telegramId: data['user']?['id']?.toString(),
              username: data['user']?['username']?.toString(),
              firstName: data['user']?['first_name']?.toString(),
              photoUrl: data['user']?['photo_url']?.toString(),
            );

            // Save auth data
            await _saveAuthData(result);

            if (!_authCompleter!.isCompleted) {
              _authCompleter!.complete(result);
            }
          }
        }
      } catch (_) {
        // Network error — silently retry on next poll
      }
    });

    return _authCompleter!.future;
  }

  /// Save auth data to SharedPreferences.
  Future<void> _saveAuthData(TelegramAuthResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FoxConfig.keyIsAuthenticated, true);
    await prefs.setString(FoxConfig.keyAuthToken, _currentToken ?? '');
    if (result.telegramId != null) {
      await prefs.setString(FoxConfig.keyTelegramId, result.telegramId!);
    }
    if (result.username != null) {
      await prefs.setString(
          FoxConfig.keyTelegramUsername, result.username!);
    }
    if (result.firstName != null) {
      await prefs.setString(
          FoxConfig.keyTelegramFirstName, result.firstName!);
    }
    if (result.photoUrl != null) {
      await prefs.setString(
          FoxConfig.keyTelegramPhotoUrl, result.photoUrl!);
    }
    if (result.subscriptionUrl != null) {
      await prefs.setString(
          FoxConfig.keySubscriptionUrl, result.subscriptionUrl!);
    }
  }

  /// Check if user is already authenticated from previous session.
  static Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(FoxConfig.keyIsAuthenticated) ?? false;
  }

  /// Get saved subscription URL.
  static Future<String?> getSavedSubscriptionUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FoxConfig.keySubscriptionUrl);
  }

  /// Get saved user info.
  static Future<Map<String, String?>> getSavedUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'telegram_id': prefs.getString(FoxConfig.keyTelegramId),
      'username': prefs.getString(FoxConfig.keyTelegramUsername),
      'first_name': prefs.getString(FoxConfig.keyTelegramFirstName),
      'photo_url': prefs.getString(FoxConfig.keyTelegramPhotoUrl),
    };
  }

  /// Log out — clear saved auth data.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FoxConfig.keyIsAuthenticated);
    await prefs.remove(FoxConfig.keyAuthToken);
    await prefs.remove(FoxConfig.keyTelegramId);
    await prefs.remove(FoxConfig.keyTelegramUsername);
    await prefs.remove(FoxConfig.keyTelegramFirstName);
    await prefs.remove(FoxConfig.keyTelegramPhotoUrl);
    await prefs.remove(FoxConfig.keySubscriptionUrl);
  }

  /// Cancel ongoing auth flow.
  void cancel() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(TelegramAuthResult(
        success: false,
        error: 'Авторизация отменена',
      ));
    }
    _authCompleter = null;
    _currentToken = null;
  }
}
