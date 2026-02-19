import 'dart:async';
import 'dart:convert';

import 'package:foxcloud/config/fox_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A connected VPN device.
class VpnDevice {
  final String os;
  final String model;
  final String osVer;
  final String hwid;
  final String hwidFull;
  final String created;

  const VpnDevice({
    required this.os,
    required this.model,
    required this.osVer,
    required this.hwid,
    this.hwidFull = '',
    required this.created,
  });
}

/// User account info from the server.
class UserAccountInfo {
  final String? login;
  final String? email;
  final String? plan;
  final String? expireAt;
  final int balance;
  final int deviceCount;
  final int deviceLimit;
  final bool telegramLinked;
  final String telegramName;

  const UserAccountInfo({
    this.login,
    this.email,
    this.plan,
    this.expireAt,
    this.balance = 0,
    this.deviceCount = 0,
    this.deviceLimit = 6,
    this.telegramLinked = false,
    this.telegramName = '',
  });
}

/// Результат генерации кода привязки Telegram.
class TelegramLinkResult {
  final bool success;
  final String? code;
  final String? botUsername;
  final String? error;

  const TelegramLinkResult({
    required this.success,
    this.code,
    this.botUsername,
    this.error,
  });
}

/// Забаненное устройство.
class BannedDevice {
  final String hwid;
  final String deviceOs;
  final String deviceModel;
  final String bannedAt;

  const BannedDevice({
    required this.hwid,
    this.deviceOs = '',
    this.deviceModel = '',
    this.bannedAt = '',
  });
}

/// Результат бана/разбана устройства.
class DeviceActionResult {
  final bool success;
  final String? message;
  final String? newSubscriptionUrl;
  final String? error;

  const DeviceActionResult({
    required this.success,
    this.message,
    this.newSubscriptionUrl,
    this.error,
  });
}

/// Result of devices fetch.
class DevicesResult {
  final bool success;
  final List<VpnDevice> devices;
  final int count;
  final int limit;
  final String? error;

  const DevicesResult({
    required this.success,
    this.devices = const [],
    this.count = 0,
    this.limit = 6,
    this.error,
  });
}

/// A VPN plan available for purchase.
class VpnPlan {
  final String id;
  final String name;
  final int price;

  const VpnPlan({
    required this.id,
    required this.name,
    required this.price,
  });
}

/// Result of a payment creation.
class PaymentCreationResult {
  final bool success;
  final String? orderId;
  final String? confirmationUrl;
  final String? error;

  PaymentCreationResult({
    required this.success,
    this.orderId,
    this.confirmationUrl,
    this.error,
  });
}

/// Status of a payment being polled.
enum PaymentPollStatus { pending, succeeded, canceled, unknown }

class PaymentStatusResult {
  final PaymentPollStatus status;
  final String? subscriptionUrl;
  final String? login;
  final String? password;
  final String? email;

  PaymentStatusResult({
    required this.status,
    this.subscriptionUrl,
    this.login,
    this.password,
    this.email,
  });
}

/// Результат продления подписки с баланса.
class ExtendResult {
  final bool success;
  final String? message;
  final String? newExpireAt;
  final int? balance;
  // Если не хватает средств:
  final bool needTopup;
  final int? currentBalance;
  final int? price;
  final int? topupAmount;
  final String? planName;
  final int? discountPercent;
  final String? error;

  const ExtendResult({
    required this.success,
    this.message,
    this.newExpireAt,
    this.balance,
    this.needTopup = false,
    this.currentBalance,
    this.price,
    this.topupAmount,
    this.planName,
    this.discountPercent,
    this.error,
  });
}

/// Результат создания платежа на пополнение баланса.
class TopupResult {
  final bool success;
  final String? confirmationUrl;
  final String? orderId;
  final String? error;

  const TopupResult({
    required this.success,
    this.confirmationUrl,
    this.orderId,
    this.error,
  });
}

/// Результат проверки статуса пополнения.
class TopupStatusResult {
  final String status; // 'succeeded', 'pending', 'canceled', 'unknown', 'error'
  final double? balance;
  final String? error;

  const TopupStatusResult({
    required this.status,
    this.balance,
    this.error,
  });
}

/// Service for purchasing VPN subscriptions through the foxcloud_web backend.
class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();

  /// Base URL for the API (same server as auth, but root).
  static String get _baseUrl {
    // authServerUrl = "https://buy.vpnghost.space/api/auth"
    // We need       = "https://buy.vpnghost.space"
    final authUrl = FoxConfig.authServerUrl;
    final idx = authUrl.indexOf('/api/');
    if (idx != -1) return authUrl.substring(0, idx);
    return authUrl;
  }

  /// Fetch available plans with prices.
  Future<List<VpnPlan>> getPlans() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/prices'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prices = data['prices'] as Map<String, dynamic>;
        final names = data['names'] as Map<String, dynamic>;

        final plans = <VpnPlan>[];
        for (final entry in prices.entries) {
          plans.add(VpnPlan(
            id: entry.key,
            name: names[entry.key]?.toString() ?? entry.key,
            price: (entry.value as num).toInt(),
          ));
        }

        // Sort: trial first, then by price ascending
        plans.sort((a, b) {
          if (a.id == 'trial') return -1;
          if (b.id == 'trial') return 1;
          return a.price.compareTo(b.price);
        });

        return plans;
      }
    } catch (_) {}
    return [];
  }

  /// Create a payment for the given plan and email.
  /// Returns the YooKassa confirmation URL for the user to pay.
  Future<PaymentCreationResult> createPayment({
    required String email,
    required String planId,
    String? referralCode,
  }) async {
    try {
      final body = <String, dynamic>{
        'email': email,
        'plan': planId,
      };
      if (referralCode != null && referralCode.isNotEmpty) {
        body['ref'] = referralCode;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/create-payment'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return PaymentCreationResult(
            success: true,
            orderId: data['order_id']?.toString(),
            confirmationUrl: data['confirmation_url']?.toString(),
          );
        }
        return PaymentCreationResult(
          success: false,
          error: data['error']?.toString() ?? 'Неизвестная ошибка',
        );
      }
      return PaymentCreationResult(
        success: false,
        error: 'Ошибка сервера: ${response.statusCode}',
      );
    } catch (e) {
      return PaymentCreationResult(
        success: false,
        error: 'Ошибка сети: $e',
      );
    }
  }

  /// Poll payment status once.
  Future<PaymentStatusResult> checkPaymentStatus(String orderId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/payment-status?payment_id=$orderId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = switch (data['status']) {
          'succeeded' => PaymentPollStatus.succeeded,
          'canceled' => PaymentPollStatus.canceled,
          'pending' => PaymentPollStatus.pending,
          _ => PaymentPollStatus.unknown,
        };

        return PaymentStatusResult(
          status: status,
          subscriptionUrl: data['subscription_url']?.toString(),
          login: data['login']?.toString(),
          password: data['password']?.toString(),
          email: data['email']?.toString(),
        );
      }
    } catch (_) {}

    return PaymentStatusResult(status: PaymentPollStatus.unknown);
  }

  /// Poll payment status until succeeded, canceled, or timeout.
  /// Returns a stream of status updates.
  Stream<PaymentStatusResult> pollPaymentStatus(
    String orderId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 10),
  }) {
    late StreamController<PaymentStatusResult> controller;
    Timer? timer;
    DateTime? startTime;

    controller = StreamController<PaymentStatusResult>(
      onListen: () {
        startTime = DateTime.now();
        timer = Timer.periodic(interval, (_) async {
          if (DateTime.now().difference(startTime!).compareTo(timeout) > 0) {
            timer?.cancel();
            controller.add(PaymentStatusResult(
                status: PaymentPollStatus.unknown));
            await controller.close();
            return;
          }

          final result = await checkPaymentStatus(orderId);
          controller.add(result);

          if (result.status == PaymentPollStatus.succeeded ||
              result.status == PaymentPollStatus.canceled) {
            timer?.cancel();
            await controller.close();
          }
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Login with credentials and get the subscription URL.
  Future<LoginResult> loginWithCredentials({
    required String login,
    required String password,
  }) async {
    final trimmedLogin = login.trim();
    final trimmedPassword = password.trim();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'login': trimmedLogin, 'password': trimmedPassword}),
          )
          .timeout(const Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return LoginResult(
          success: true,
          subscriptionUrl: data['subscription_url']?.toString(),
        );
      }

      return LoginResult(
        success: false,
        error: data['error']?.toString() ?? 'Неверный логин или пароль',
      );
    } catch (e) {
      return LoginResult(
        success: false,
        error: 'Ошибка сети: $e',
      );
    }
  }

  /// Get the saved subscription URL for mobile API auth.
  Future<String?> _getSubscriptionUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FoxConfig.keySubscriptionUrl);
  }

  /// Get current user account info.
  Future<UserAccountInfo?> getAccountInfo() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/me'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return UserAccountInfo(
            login: data['login']?.toString(),
            email: data['email']?.toString(),
            plan: data['plan']?.toString(),
            expireAt: data['expire_at']?.toString(),
            balance: (data['balance'] as num?)?.toInt() ?? 0,
            deviceCount: (data['device_count'] as num?)?.toInt() ?? 0,
            deviceLimit: (data['device_limit'] as num?)?.toInt() ?? 6,
            telegramLinked: data['telegram_linked'] == true,
            telegramName: data['telegram_name']?.toString() ?? '',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get connected devices list.
  Future<DevicesResult> getDevices() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const DevicesResult(success: false, error: 'Нет подписки');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/devices'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final devicesJson = data['devices'] as List<dynamic>? ?? [];
          final devices = devicesJson
              .map((d) => VpnDevice(
                    os: d['os']?.toString() ?? '—',
                    model: d['model']?.toString() ?? '—',
                    osVer: d['os_ver']?.toString() ?? '',
                    hwid: d['hwid']?.toString() ?? '',
                    hwidFull: d['hwid_full']?.toString() ?? d['hwid']?.toString() ?? '',
                    created: d['created']?.toString() ?? '',
                  ))
              .toList();

          return DevicesResult(
            success: true,
            devices: devices,
            count: (data['count'] as num?)?.toInt() ?? devices.length,
            limit: (data['limit'] as num?)?.toInt() ?? 6,
          );
        }
      }
    } catch (e) {
      return DevicesResult(success: false, error: 'Ошибка сети: $e');
    }
    return const DevicesResult(success: false, error: 'Ошибка сервера');
  }

  /// Сгенерировать код привязки Telegram.
  Future<TelegramLinkResult> generateTelegramLinkCode() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const TelegramLinkResult(success: false, error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/telegram-link';
      print('[PurchaseService] generateTelegramLinkCode → POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'x-sub-url': subUrl,
          'Content-Type': 'application/json',
        },
        body: '{}',
      ).timeout(const Duration(seconds: 10));

      print('[PurchaseService] telegram-link status=${response.statusCode} body=${response.body}');

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return TelegramLinkResult(
          success: true,
          code: data['code']?.toString(),
          botUsername: data['bot_username']?.toString(),
        );
      }

      return TelegramLinkResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка генерации кода',
      );
    } catch (e) {
      return TelegramLinkResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Отвязать Telegram.
  Future<bool> unlinkTelegram() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return false;

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/mobile/telegram-unlink'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Забанить устройство.
  Future<DeviceActionResult> banDevice(String hwid, {String os = '—', String model = '—'}) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const DeviceActionResult(success: false, error: 'Нет подписки');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/mobile/devices/ban'),
        headers: {'Content-Type': 'application/json', 'x-sub-url': subUrl},
        body: json.encode({'hwid': hwid, 'os': os, 'model': model}),
      ).timeout(const Duration(seconds: 30));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return DeviceActionResult(
          success: true,
          message: data['message']?.toString(),
          newSubscriptionUrl: data['new_subscription_url']?.toString(),
        );
      }

      return DeviceActionResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка блокировки',
      );
    } catch (e) {
      return DeviceActionResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Разбанить устройство.
  Future<DeviceActionResult> unbanDevice(String hwid) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const DeviceActionResult(success: false, error: 'Нет подписки');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/mobile/devices/unban'),
        headers: {'Content-Type': 'application/json', 'x-sub-url': subUrl},
        body: json.encode({'hwid': hwid}),
      ).timeout(const Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return DeviceActionResult(
          success: true,
          message: data['message']?.toString(),
        );
      }

      return DeviceActionResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка разблокировки',
      );
    } catch (e) {
      return DeviceActionResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить список забаненных устройств.
  Future<List<BannedDevice>> getBannedDevices() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/devices/banned'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      print('[PurchaseService] getBannedDevices status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['devices'] as List<dynamic>? ?? [];
          return list.map((d) => BannedDevice(
            hwid: d['hwid']?.toString() ?? '',
            deviceOs: d['device_os']?.toString() ?? '',
            deviceModel: d['device_model']?.toString() ?? '',
            bannedAt: d['banned_at']?.toString() ?? '',
          )).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Удалить устройство (по HWID).
  Future<DeviceActionResult> deleteDevice(String hwid) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const DeviceActionResult(success: false, error: 'Нет подписки');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/mobile/devices/delete'),
        headers: {'Content-Type': 'application/json', 'x-sub-url': subUrl},
        body: json.encode({'hwid': hwid}),
      ).timeout(const Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return DeviceActionResult(
          success: true,
          message: data['message']?.toString(),
        );
      }

      return DeviceActionResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка удаления',
      );
    } catch (e) {
      return DeviceActionResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Apply a promo code.
  Future<PromoResult> applyPromoCode(String code) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const PromoResult(success: false, error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/promo/apply';
      print('[PurchaseService] applyPromoCode → POST $url code="${code.trim()}"');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-sub-url': subUrl,
            },
            body: json.encode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      print('[PurchaseService] applyPromoCode status=${response.statusCode} body=${response.body}');
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return PromoResult(
          success: true,
          message: data['message']?.toString(),
          type: data['type']?.toString(),
          value: (data['value'] as num?)?.toDouble(),
          balance: (data['balance'] as num?)?.toDouble(),
        );
      }

      // Поддержка FastAPI validation errors (422) — detail вместо error
      final errorMsg = data['error']?.toString()
          ?? data['detail']?.toString()
          ?? 'Ошибка применения промокода';
      return PromoResult(success: false, error: errorMsg);
    } catch (e, st) {
      print('[PurchaseService] applyPromoCode EXCEPTION: $e\n$st');
      return PromoResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Применить реферальный код (после регистрации).
  Future<PromoResult> applyReferralCode(String code) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const PromoResult(success: false, error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/referral/apply';
      print('[PurchaseService] applyReferralCode → POST $url code="${code.trim()}"');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-sub-url': subUrl,
            },
            body: json.encode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      print('[PurchaseService] applyReferralCode status=${response.statusCode} body=${response.body}');
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return PromoResult(
          success: true,
          message: data['message']?.toString(),
        );
      }

      final errorMsg = data['error']?.toString()
          ?? data['detail']?.toString()
          ?? 'Ошибка применения кода';
      return PromoResult(success: false, error: errorMsg);
    } catch (e, st) {
      print('[PurchaseService] applyReferralCode EXCEPTION: $e\n$st');
      return PromoResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Получить информацию о реферальной программе.
  Future<ReferralInfo> getReferralInfo() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const ReferralInfo(error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/referral';
      print('[PurchaseService] getReferralInfo → GET $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 15));

      print('[PurchaseService] getReferralInfo status=${response.statusCode} body=${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final referralsList = (data['referrals'] as List<dynamic>? ?? [])
              .map((r) => ReferralEntry(
                    email: r['email']?.toString() ?? '—',
                    confirmed: r['confirmed'] == true,
                    isTrial: r['is_trial'] == true,
                    createdAt: r['created_at']?.toString(),
                    confirmedAt: r['confirmed_at']?.toString(),
                  ))
              .toList();

          final tiersList = (data['tiers'] as List<dynamic>? ?? [])
              .map((t) => ReferralTier(
                    count: (t['count'] as num?)?.toInt() ?? 0,
                    discount: (t['discount'] as num?)?.toInt() ?? 0,
                  ))
              .toList();

          return ReferralInfo(
            success: true,
            code: data['code']?.toString() ?? '',
            link: data['link']?.toString() ?? '',
            confirmedCount: (data['confirmed_count'] as num?)?.toInt() ?? 0,
            discountPercent: (data['discount_percent'] as num?)?.toInt() ?? 0,
            nextTier: data['next_tier'] as Map<String, dynamic>?,
            referrals: referralsList,
            tiers: tiersList,
            hasReferrer: data['has_referrer'] == true,
            bonusAvailable: data['bonus_available'] == true,
            bonusReceived: data['bonus_received'] == true,
          );
        }
      }
    } catch (e, st) {
      print('[PurchaseService] getReferralInfo EXCEPTION: $e\n$st');
    }
    return const ReferralInfo(error: 'Ошибка загрузки реферальной информации');
  }

  /// Продление подписки с баланса.
  /// Если баланс достаточен — списывает и продлевает.
  /// Если нет — возвращает needTopup=true и сумму доплаты.
  Future<ExtendResult> extendWithBalance(String planId) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const ExtendResult(success: false, error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/extend';
      print('[PurchaseService] extendWithBalance → POST $url plan=$planId');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-sub-url': subUrl,
            },
            body: json.encode({'plan': planId}),
          )
          .timeout(const Duration(seconds: 15));

      print('[PurchaseService] extendWithBalance status=${response.statusCode}');
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return ExtendResult(
          success: true,
          message: data['message']?.toString(),
          newExpireAt: data['new_expire_at']?.toString(),
          balance: (data['balance'] as num?)?.toInt(),
        );
      }

      // 402 — недостаточно средств, нужна доплата
      if (response.statusCode == 402 &&
          data['error'] == 'insufficient_balance') {
        return ExtendResult(
          success: false,
          needTopup: true,
          currentBalance: (data['balance'] as num?)?.toInt() ?? 0,
          price: (data['price'] as num?)?.toInt() ?? 0,
          topupAmount: (data['need_topup'] as num?)?.toInt() ?? 0,
          planName: data['plan_name']?.toString(),
          discountPercent: (data['discount_percent'] as num?)?.toInt() ?? 0,
        );
      }

      return ExtendResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка продления',
      );
    } catch (e, st) {
      print('[PurchaseService] extendWithBalance EXCEPTION: $e\n$st');
      return ExtendResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Создать платёж на пополнение баланса.
  Future<TopupResult> createTopupPayment(int amount) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const TopupResult(success: false, error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/topup';
      print('[PurchaseService] createTopupPayment → POST $url amount=$amount');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-sub-url': subUrl,
            },
            body: json.encode({'amount': amount}),
          )
          .timeout(const Duration(seconds: 15));

      print('[PurchaseService] createTopupPayment status=${response.statusCode}');
      final data = json.decode(response.body);

      if (data['success'] == true && data['confirmation_url'] != null) {
        return TopupResult(
          success: true,
          confirmationUrl: data['confirmation_url']?.toString(),
          orderId: data['order_id']?.toString(),
        );
      }

      return TopupResult(
        success: false,
        error: data['error']?.toString() ?? 'Ошибка создания платежа',
      );
    } catch (e, st) {
      print('[PurchaseService] createTopupPayment EXCEPTION: $e\n$st');
      return TopupResult(success: false, error: 'Ошибка сети: $e');
    }
  }

  /// Проверить статус пополнения по order_id.
  /// Возвращает: 'succeeded', 'pending', 'canceled', 'unknown', 'error'
  Future<TopupStatusResult> checkTopupStatus(String orderId) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) {
        return const TopupStatusResult(status: 'error', error: 'Нет подписки');
      }

      final url = '$_baseUrl/api/auth/mobile/topup/status?order_id=${Uri.encodeQueryComponent(orderId)}';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'x-sub-url': subUrl},
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      return TopupStatusResult(
        status: data['status']?.toString() ?? 'unknown',
        balance: (data['balance'] as num?)?.toDouble(),
      );
    } catch (e) {
      return TopupStatusResult(status: 'error', error: '$e');
    }
  }

  /// Fetch active server announcements for display in the app.
  Future<List<ServerAnnouncement>> fetchAnnouncements() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/announcements'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['announcements'] as List<dynamic>? ?? [];
          return list
              .map((a) {
                final btnList = (a['buttons'] as List<dynamic>? ?? [])
                    .map((b) => AnnouncementButton(
                          label: b['label']?.toString() ?? '',
                          url: b['url']?.toString() ?? '',
                        ))
                    .where((b) => b.label.isNotEmpty)
                    .toList();
                return ServerAnnouncement(
                  id: (a['id'] as num?)?.toInt() ?? 0,
                  text: a['text']?.toString() ?? '',
                  bgColor: a['bg_color']?.toString() ?? '',
                  textColor: a['text_color']?.toString() ?? '',
                  isDismissible: a['is_dismissible'] != 0 && a['is_dismissible'] != false,
                  buttons: btnList,
                );
              })
              .where((a) => a.text.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch push notifications newer than [afterId].
  Future<List<ServerPushNotification>> fetchNewNotifications(int afterId) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/notifications?after_id=$afterId'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['notifications'] as List<dynamic>? ?? [];
          return list
              .map((n) => ServerPushNotification(
                    id: (n['id'] as num?)?.toInt() ?? 0,
                    title: n['title']?.toString() ?? '',
                    message: n['message']?.toString() ?? '',
                  ))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }
}

/// Result of a login attempt.
class LoginResult {
  final bool success;
  final String? subscriptionUrl;
  final String? error;

  LoginResult({
    required this.success,
    this.subscriptionUrl,
    this.error,
  });
}

/// Referral tier info.
class ReferralTier {
  final int count;
  final int discount;

  const ReferralTier({required this.count, required this.discount});
}

/// Next referral tier info.
class NextReferralTier {
  final int need;
  final int discount;

  const NextReferralTier({required this.need, required this.discount});
}

/// A single referred user.
class ReferralEntry {
  final String email;
  final bool confirmed;
  final bool isTrial;
  final String? createdAt;
  final String? confirmedAt;

  const ReferralEntry({
    required this.email,
    this.confirmed = false,
    this.isTrial = false,
    this.createdAt,
    this.confirmedAt,
  });
}

/// Full referral info response from server.
class ReferralInfo {
  final bool success;
  final String code;
  final String link;
  final int confirmedCount;
  final int discountPercent;
  final Map<String, dynamic>? nextTier;
  final List<ReferralEntry> referrals;
  final List<ReferralTier> tiers;
  final bool hasReferrer;
  final bool bonusAvailable;
  final bool bonusReceived;
  final String? error;

  const ReferralInfo({
    this.success = false,
    this.code = '',
    this.link = '',
    this.confirmedCount = 0,
    this.discountPercent = 0,
    this.nextTier,
    this.referrals = const [],
    this.tiers = const [],
    this.hasReferrer = false,
    this.bonusAvailable = false,
    this.bonusReceived = false,
    this.error,
  });
}

/// Result of applying a promo code.
class PromoResult {
  final bool success;
  final String? message;
  final String? type;
  final double? value;
  final double? balance;
  final String? error;

  const PromoResult({
    required this.success,
    this.message,
    this.type,
    this.value,
    this.balance,
    this.error,
  });
}

/// Server-managed announcement for display in the app.
class ServerAnnouncement {
  final int id;
  final String text;
  final String bgColor;
  final String textColor;
  final bool isDismissible;
  final List<AnnouncementButton> buttons;

  const ServerAnnouncement({
    required this.id,
    required this.text,
    this.bgColor = '',
    this.textColor = '',
    this.isDismissible = true,
    this.buttons = const [],
  });
}

/// A button attached to a server announcement.
class AnnouncementButton {
  final String label;
  final String url;

  const AnnouncementButton({required this.label, this.url = ''});
}

/// Server push notification for the notification shade.
class ServerPushNotification {
  final int id;
  final String title;
  final String message;

  const ServerPushNotification({
    required this.id,
    required this.title,
    required this.message,
  });
}
