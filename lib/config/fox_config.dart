/// FoxCloud configuration constants.
/// Update these values to match your deployment.
class FoxConfig {
  FoxConfig._();

  /// Telegram bot username (without @) used for auth deep links.
  /// TODO: Replace with your Telegram bot username.
  static const String telegramBotUsername = 'your_bot_username';

  /// Auth server base URL (FastAPI backend).
  /// Should point to the same server running foxcloud_web (main.py).
  /// TODO: Replace with your server URL.
  static const String authServerUrl = 'https://your-domain.com/api/auth';

  /// Polling interval when waiting for Telegram auth confirmation.
  static const Duration authPollInterval = Duration(seconds: 2);

  /// Maximum time to wait for Telegram auth before timeout.
  static const Duration authTimeout = Duration(minutes: 5);

  /// SharedPreferences keys.
  static const String keyAuthToken = 'fox_auth_token';
  static const String keyTelegramId = 'fox_telegram_id';
  static const String keyTelegramUsername = 'fox_telegram_username';
  static const String keyTelegramFirstName = 'fox_telegram_first_name';
  static const String keyTelegramPhotoUrl = 'fox_telegram_photo_url';
  static const String keySubscriptionUrl = 'fox_subscription_url';
  static const String keyIsAuthenticated = 'fox_is_authenticated';

  /// Saved credentials from last purchase (for auto-login).
  static const String keySavedLogin = 'fox_saved_login';
  static const String keySavedPassword = 'fox_saved_password';
}
