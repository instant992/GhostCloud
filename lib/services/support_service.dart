import 'dart:convert';
import 'dart:typed_data';

import 'package:foxcloud/config/fox_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Одно сообщение в чате поддержки.
class SupportMessage {
  final int id;
  final String sender; // 'user' | 'admin'
  final String? text;
  final String? imageUrl;
  final bool isRead;
  final String createdAt;

  const SupportMessage({
    required this.id,
    required this.sender,
    this.text,
    this.imageUrl,
    this.isRead = false,
    required this.createdAt,
  });
}

/// Краткая информация о тикете (для списка истории).
class SupportTicketInfo {
  final int id;
  final String status;
  final int messageCount;
  final String? firstMessage;
  final String createdAt;
  final String updatedAt;

  const SupportTicketInfo({
    required this.id,
    required this.status,
    required this.messageCount,
    this.firstMessage,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Сервис для работы с чатом поддержки.
class SupportService {
  SupportService._();
  static final instance = SupportService._();

  static String get _baseUrl {
    final authUrl = FoxConfig.authServerUrl;
    final idx = authUrl.indexOf('/api/');
    if (idx != -1) return authUrl.substring(0, idx);
    return authUrl;
  }

  Future<String?> _getSubscriptionUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FoxConfig.keySubscriptionUrl);
  }

  /// Отправить сообщение в поддержку.
  /// [imageBytes] — JPEG/PNG в виде байтов (опционально).
  Future<bool> sendMessage({String? text, Uint8List? imageBytes}) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return false;

      final body = <String, dynamic>{};
      if (text != null && text.trim().isNotEmpty) {
        body['text'] = text.trim();
      }
      if (imageBytes != null) {
        body['image'] = base64Encode(imageBytes);
      }
      if (body.isEmpty) return false;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/mobile/support/send'),
            headers: {
              'x-sub-url': subUrl,
              'Content-Type': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      // ignore
    }
    return false;
  }

  /// Получить сообщения (после указанного id для polling).
  Future<List<SupportMessage>> getMessages({int afterId = 0}) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/auth/mobile/support/messages?after_id=$afterId'),
            headers: {'x-sub-url': subUrl},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['messages'] as List? ?? [];
          return list.map((m) {
            return SupportMessage(
              id: m['id'] as int,
              sender: m['sender'] as String,
              text: m['text'] as String?,
              imageUrl: m['image_url'] as String?,
              isRead: m['is_read'] == true,
              createdAt: m['created_at'] as String? ?? '',
            );
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Закрыть тикет.
  Future<bool> closeTicket() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return false;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/mobile/support/close'),
            headers: {'x-sub-url': subUrl},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Получить URL аватара сотрудника поддержки.
  Future<String?> getAdminAvatarUrl() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/auth/mobile/support/avatar'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['avatar_url'] != null) {
          final url = data['avatar_url'] as String;
          return url.startsWith('http') ? url : '$_baseUrl$url';
        }
      }
    } catch (_) {}
    return null;
  }

  /// Получить список всех обращений (история).
  Future<List<SupportTicketInfo>> getHistory() async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/auth/mobile/support/history'),
            headers: {'x-sub-url': subUrl},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['tickets'] as List? ?? [];
          return list.map((t) {
            return SupportTicketInfo(
              id: t['id'] as int,
              status: t['status'] as String,
              messageCount: t['message_count'] as int? ?? 0,
              firstMessage: t['first_message'] as String?,
              createdAt: t['created_at'] as String? ?? '',
              updatedAt: t['updated_at'] as String? ?? '',
            );
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Получить сообщения конкретного тикета (для просмотра истории).
  Future<List<SupportMessage>> getTicketMessages(int ticketId) async {
    try {
      final subUrl = await _getSubscriptionUrl();
      if (subUrl == null || subUrl.isEmpty) return [];

      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/auth/mobile/support/history/$ticketId'),
            headers: {'x-sub-url': subUrl},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final list = data['messages'] as List? ?? [];
          return list.map((m) {
            return SupportMessage(
              id: m['id'] as int,
              sender: m['sender'] as String,
              text: m['text'] as String?,
              imageUrl: m['image_url'] as String?,
              isRead: m['is_read'] == true,
              createdAt: m['created_at'] as String? ?? '',
            );
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Полный URL картинки.
  String fullImageUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    return '$_baseUrl$relativeUrl';
  }
}
