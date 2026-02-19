import 'package:foxcloud/services/fcm_service.dart';
import 'package:foxcloud/services/telegram_auth_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foxcloud/config/fox_config.dart';

part 'auth.g.dart';

/// Auth state — tracks whether the user is authenticated.
enum FoxAuthStatus {
  /// Initial state, checking saved credentials.
  checking,

  /// Not authenticated — show login screen.
  unauthenticated,

  /// Waiting for Telegram bot confirmation.
  waitingForTelegram,

  /// Authenticated — proceed to main app.
  authenticated,

  /// Error state.
  error,
}

class FoxAuthState {
  final FoxAuthStatus status;
  final String? subscriptionUrl;
  final String? username;
  final String? firstName;
  final String? errorMessage;

  const FoxAuthState({
    required this.status,
    this.subscriptionUrl,
    this.username,
    this.firstName,
    this.errorMessage,
  });

  FoxAuthState copyWith({
    FoxAuthStatus? status,
    String? subscriptionUrl,
    String? username,
    String? firstName,
    String? errorMessage,
  }) {
    return FoxAuthState(
      status: status ?? this.status,
      subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

@riverpod
class FoxAuth extends _$FoxAuth {
  @override
  FoxAuthState build() {
    // Check saved auth on startup
    _checkSavedAuth();
    return const FoxAuthState(status: FoxAuthStatus.checking);
  }

  Future<void> _checkSavedAuth() async {
    final isAuth = await TelegramAuthService.isAuthenticated();
    if (isAuth) {
      final userInfo = await TelegramAuthService.getSavedUserInfo();
      // Don't include subscriptionUrl on restart — only on first login/purchase.
      // Including it would trigger _AuthGate listener → addProfileFormURL → duplicate profile.
      state = FoxAuthState(
        status: FoxAuthStatus.authenticated,
        username: userInfo['username'],
        firstName: userInfo['first_name'],
      );
    } else {
      state = const FoxAuthState(status: FoxAuthStatus.unauthenticated);
    }
  }

  /// Start Telegram auth flow.
  Future<void> startTelegramAuth() async {
    state = state.copyWith(status: FoxAuthStatus.waitingForTelegram);

    final result = await TelegramAuthService.instance.startAuth();

    if (result.success) {
      state = FoxAuthState(
        status: FoxAuthStatus.authenticated,
        subscriptionUrl: result.subscriptionUrl,
        username: result.username,
        firstName: result.firstName,
      );
      // Register FCM token with server after successful auth
      FcmService.reRegisterToken();
    } else {
      state = FoxAuthState(
        status: FoxAuthStatus.error,
        errorMessage: result.error,
      );
    }
  }

  /// Cancel ongoing auth.
  void cancelAuth() {
    TelegramAuthService.instance.cancel();
    state = const FoxAuthState(status: FoxAuthStatus.unauthenticated);
  }

  /// Log out.
  Future<void> logout() async {
    await TelegramAuthService.logout();
    state = const FoxAuthState(status: FoxAuthStatus.unauthenticated);
  }

  /// Skip auth and go to unauthenticated main app (for manual subscription URL input).
  Future<void> skipAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FoxConfig.keyIsAuthenticated, true);
    state = const FoxAuthState(status: FoxAuthStatus.authenticated);
  }

  /// Skip auth after purchasing — auto-add subscription URL.
  Future<void> skipAuthWithSubscription(String subscriptionUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FoxConfig.keyIsAuthenticated, true);
    await prefs.setString(FoxConfig.keySubscriptionUrl, subscriptionUrl);
    state = FoxAuthState(
      status: FoxAuthStatus.authenticated,
      subscriptionUrl: subscriptionUrl,
    );
    // Register FCM token with server after getting subscription
    FcmService.reRegisterToken();
  }
}
