import 'dart:convert';
import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TgProxyBanner extends ConsumerStatefulWidget {
  const TgProxyBanner({super.key});

  @override
  ConsumerState<TgProxyBanner> createState() => _TgProxyBannerState();
}

class _TgProxyBannerState extends ConsumerState<TgProxyBanner> {
  bool _loading = true;
  bool _enabled = false;
  String _text = '';
  String _buttonText = '';
  String _url = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String get _baseUrl {
    final authUrl = FoxConfig.authServerUrl;
    final idx = authUrl.indexOf('/api/');
    if (idx != -1) return authUrl.substring(0, idx);
    return authUrl;
  }

  Future<String?> _getSubUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FoxConfig.keySubscriptionUrl);
  }

  Future<void> _load() async {
    try {
      final subUrl = await _getSubUrl();
      if (subUrl == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/mobile/tg-proxy'),
        headers: {'x-sub-url': subUrl},
      ).timeout(const Duration(seconds: 10));

      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _enabled = data['enabled'] == true;
          _text = data['text'] ?? '';
          _buttonText = data['button_text'] ?? 'Подключить';
          _url = data['url'] ?? '';
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_enabled || _url.isEmpty) {
      return const SizedBox.shrink();
    }

    const tgBlue = Color(0xFF2AABEE);
    const tgDark = Color(0xFF229ED9);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [tgBlue.withValues(alpha: 0.18), tgDark.withValues(alpha: 0.12)]
              : [tgBlue.withValues(alpha: 0.12), tgDark.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tgBlue.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => globalState.openUrl(_url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Text
                Expanded(
                  child: Text(
                    _text,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: tgBlue,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: tgBlue.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.telegram, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
