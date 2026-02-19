import 'dart:ui';
import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/models/models.dart';
import 'package:foxcloud/providers/providers.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/views/purchase/plans_view.dart';
import 'package:foxcloud/views/purchase/payment_webview.dart';
import 'package:foxcloud/views/purchase/renew_page.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Dashboard widget showing connected devices and renewal button.
class SubscriptionManageWidget extends ConsumerStatefulWidget {
  const SubscriptionManageWidget({super.key});

  @override
  ConsumerState<SubscriptionManageWidget> createState() =>
      _SubscriptionManageWidgetState();
}

class _SubscriptionManageWidgetState
    extends ConsumerState<SubscriptionManageWidget> {
  DevicesResult? _devicesResult;
  UserAccountInfo? _accountInfo;
  bool _isLoading = true;
  bool _hasError = false;

  // IP address state
  String? _publicIp;
  bool _ipLoading = true;
  bool _ipBlurred = true;
  bool? _prevVpnRunning;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchIP();
  }

  Future<void> _fetchIP() async {
    setState(() => _ipLoading = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.ipify.org'),
      ).timeout(const Duration(seconds: 5));
      if (mounted && response.statusCode == 200) {
        setState(() {
          _publicIp = response.body.trim();
          _ipLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _publicIp = null;
          _ipLoading = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final results = await Future.wait([
        PurchaseService.instance.getDevices(),
        PurchaseService.instance.getAccountInfo(),
      ]);

      if (mounted) {
        setState(() {
          _devicesResult = results[0] as DevicesResult;
          _accountInfo = results[1] as UserAccountInfo?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  String _getDeviceIcon(String os) {
    final lower = os.toLowerCase();
    if (lower.contains('android')) return '📱';
    if (lower.contains('ios') || lower.contains('iphone') || lower.contains('ipad')) return '📱';
    if (lower.contains('windows')) return '💻';
    if (lower.contains('mac') || lower.contains('darwin')) return '🖥️';
    if (lower.contains('linux')) return '🐧';
    return '📟';
  }

  String _formatTrafficGb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 100) return '${gb.toStringAsFixed(0)} ГБ';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} ГБ';
    if (gb >= 1) return '${gb.toStringAsFixed(2)} ГБ';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} МБ';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(0)} КБ';
  }

  void _handleRenew() async {
    final renewed = await RenewPage.show(context);
    if (renewed && mounted) {
      _loadData(); // Обновляем данные после продления
    }
  }

  /// Пополнить баланс.
  void _handleTopup() async {
    final amountController = TextEditingController(text: '100');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Пополнить баланс'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Сумма (₽)',
            prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixText: '₽',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(amountController.text.trim());
              if (val != null && val >= 10) {
                Navigator.of(ctx).pop(val);
              }
            },
            child: const Text('Пополнить'),
          ),
        ],
      ),
    );

    if (amount == null || !mounted) return;

    // Show loading
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Создание платежа...'), duration: Duration(seconds: 2)),
    );

    final result = await PurchaseService.instance.createTopupPayment(amount);
    if (!mounted) return;

    if (result.success && result.confirmationUrl != null) {
      await PaymentWebView.show(context, result.confirmationUrl!);
      if (mounted) {
        _loadData(); // Обновляем баланс после оплаты
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Ошибка создания платежа')),
      );
    }
  }

  /// Покупка новой подписки (для тех, у кого нет подписки).
  void _handleBuyNew() async {
    final subUrl = await PurchasePage.show(context);
    if (subUrl != null && subUrl.isNotEmpty && mounted) {
      // Add the new subscription profile
      final controller = globalState.appController;
      await controller.addProfileFormURL(subUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider);
    final vpnRunning = ref.watch(runTimeProvider) != null;

    // Re-fetch IP when VPN state changes
    if (_prevVpnRunning != null && _prevVpnRunning != vpnRunning) {
      Future.microtask(() => _fetchIP());
    }
    _prevVpnRunning = vpnRunning;
    
    if (profile == null) return const SizedBox.shrink();

    final subscriptionInfo = profile.subscriptionInfo;
    
    return CommonCard(
      onPressed: null,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header: Renewal section ──
            Row(
              children: [
                Icon(
                  Icons.card_membership_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizations.renewSubscription,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Refresh button
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    onPressed: _loadData,
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),

            // ── IP Address ──
            GestureDetector(
              onTap: () => setState(() => _ipBlurred = !_ipBlurred),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.language, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'IP: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Expanded(
                      child: _ipLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ImageFiltered(
                              imageFilter: _ipBlurred
                                  ? ImageFilter.blur(sigmaX: 6, sigmaY: 6)
                                  : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                              child: Text(
                                _publicIp ?? '—',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                    ),
                    Icon(
                      _ipBlurred ? Icons.visibility_off : Icons.visibility,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // ── Traffic usage ──
            if (subscriptionInfo != null && subscriptionInfo.total > 0) ...[              _buildTrafficUsage(context, subscriptionInfo),
              const SizedBox(height: 8),
            ] else if (subscriptionInfo != null && subscriptionInfo.total == 0) ...[              // Unlimited traffic — show usage in GB
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.all_inclusive, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          appLocalizations.unlimitedTraffic,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.data_usage_rounded, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Использовано: ${_formatTrafficGb(subscriptionInfo.upload + subscriptionInfo.download)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            
            // ── Subscription status ──
            if (subscriptionInfo != null) ...[
              _buildSubscriptionStatus(context, subscriptionInfo),
              const SizedBox(height: 8),
            ],
            
            // ── Balance & Renew button ──
            if (_accountInfo != null) ...[
              _buildBalanceRow(context),
              const SizedBox(height: 8),
            ],
            
            // Renew button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _handleRenew,
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Продлить подписку'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Пополнить баланс button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _handleTopup,
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: const Text('Пополнить баланс'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromoCodeDialog(BuildContext context) {
    final controller = TextEditingController();
    String? error;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Промокод'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Введите промокод',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.isEmpty) {
                        setDialogState(() => error = 'Введите промокод');
                        return;
                      }
                      setDialogState(() {
                        loading = true;
                        error = null;
                      });
                      final result = await PurchaseService.instance.applyPromoCode(code);
                      if (!ctx.mounted) return;
                      if (result.success) {
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          _loadData(); // reload account data
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message ?? 'Промокод применён!')),
                          );
                        }
                      } else {
                        setDialogState(() {
                          loading = false;
                          error = result.error ?? 'Ошибка';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionStatus(
      BuildContext context, SubscriptionInfo info) {
    final theme = Theme.of(context);
    final isPerpetual = info.expire == 0;

    String expiryText;
    Color expiryColor;
    
    if (isPerpetual) {
      expiryText = appLocalizations.subscriptionEternal;
      expiryColor = Colors.green;
    } else {
      final expireDate =
          DateTime.fromMillisecondsSinceEpoch(info.expire * 1000);
      final daysLeft = expireDate.difference(DateTime.now()).inDays;
      expiryText =
          '${appLocalizations.expiresOn} ${DateFormat('dd.MM.yyyy').format(expireDate)}';
      
      if (daysLeft <= 0) {
        expiryColor = Colors.red;
      } else if (daysLeft <= 3) {
        expiryColor = Colors.orange;
      } else {
        expiryColor = theme.colorScheme.onSurfaceVariant;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: expiryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        expiryText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: expiryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTrafficUsage(BuildContext context, SubscriptionInfo info) {
    final theme = Theme.of(context);
    final used = info.upload + info.download;
    final total = info.total;
    final progress = (total > 0) ? (used / total).clamp(0.0, 1.0) : 0.0;
    
    final usedShow = TrafficValue(value: used).show;
    final totalShow = TrafficValue(value: total).show;
    
    final progressColor = progress > 0.9
        ? Colors.red
        : progress > 0.7
            ? Colors.orange
            : theme.colorScheme.primary;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 16, color: progressColor),
              const SizedBox(width: 6),
              Text(
                '${appLocalizations.trafficUsed}: $usedShow / $totalShow',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(BuildContext context) {
    final theme = Theme.of(context);
    final balance = _accountInfo!.balance;
    
    return Row(
      children: [
        Icon(Icons.account_balance_wallet_outlined,
            size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          'Баланс: ${balance}₽',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.icon,
  });

  final VpnDevice device;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.model != '—' ? device.model : device.os,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${device.os} ${device.osVer}'.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
