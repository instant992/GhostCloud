import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/views/purchase/plans_view.dart' show PurchasePage;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Вкладка «Подписка» — информация об аккаунте, рефералы, устройства, Telegram, промокод.
class SubscriptionView extends StatefulWidget {
  const SubscriptionView({super.key});

  @override
  State<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<SubscriptionView> {
  ReferralInfo? _referralInfo;
  UserAccountInfo? _accountInfo;
  DevicesResult? _devicesResult;
  List<BannedDevice> _bannedDevices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final svc = PurchaseService.instance;

    // Загружаем каждый блок отдельно, чтобы ошибка одного не ломала остальные
    ReferralInfo? refInfo;
    UserAccountInfo? accInfo;
    DevicesResult? devResult;
    List<BannedDevice> banned = [];

    try { refInfo = await svc.getReferralInfo(); } catch (e) {
      debugPrint('[SubscriptionView] getReferralInfo error: $e');
    }
    try { accInfo = await svc.getAccountInfo(); } catch (e) {
      debugPrint('[SubscriptionView] getAccountInfo error: $e');
    }
    try { devResult = await svc.getDevices(); } catch (e) {
      debugPrint('[SubscriptionView] getDevices error: $e');
    }
    try { banned = await svc.getBannedDevices(); } catch (e) {
      debugPrint('[SubscriptionView] getBannedDevices error: $e');
    }

    if (mounted) {
      setState(() {
        _referralInfo = refInfo;
        _accountInfo = accInfo;
        _devicesResult = devResult;
        _bannedDevices = banned;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (_accountInfo != null) _buildAccountCard(cs),
          const SizedBox(height: 16),
          _buildReferralCard(cs),
          const SizedBox(height: 16),
          _buildDevicesCard(cs),
          const SizedBox(height: 16),
          _buildTelegramCard(cs),
          const SizedBox(height: 16),
          _buildPurchaseCard(cs),
          const SizedBox(height: 16),
          _buildPromoCard(cs),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─────────────────── Карточка аккаунта ───────────────────

  Widget _buildAccountCard(ColorScheme cs) {
    final acc = _accountInfo!;
    String expireText = '—';
    if (acc.expireAt != null && acc.expireAt!.isNotEmpty) {
      try {
        final dt = DateTime.parse(acc.expireAt!);
        final diff = dt.difference(DateTime.now()).inDays;
        expireText = '$diff дн.';
      } catch (_) {
        expireText = acc.expireAt!;
      }
    }

    return _card(
      cs,
      icon: Icons.person,
      title: acc.login ?? 'Аккаунт',
      children: [
        _infoRow('Тариф', acc.plan ?? '—'),
        _infoRow('Истекает через', expireText),
        _infoRow('Баланс', '${acc.balance} ₽'),
        _infoRow('Устройства', '${acc.deviceCount} / ${acc.deviceLimit}'),
      ],
    );
  }

  // ─────────────────── Реферальная программа ───────────────────

  Widget _buildReferralCard(ColorScheme cs) {
    final ref = _referralInfo;
    final hasRef = ref != null && ref.success;

    return _card(
      cs,
      icon: Icons.people,
      title: 'Реферальная программа',
      children: [
        if (!hasRef)
          Text(
            ref?.error ?? 'Не удалось загрузить реферальную информацию',
            style: const TextStyle(color: Colors.grey),
          )
        else ...[
          // ─── Ваша ссылка ───
          Row(
            children: [
              Icon(Icons.link, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text('Ваша ссылка',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ref.link,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Копировать', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: ref.link));
                    _showSnack('Ссылка скопирована');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ─── QR-код ───
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: ref.link,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: cs.primary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ─── Ваша скидка ───
          Row(
            children: [
              Icon(Icons.card_giftcard, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text('Ваша скидка',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 8),
          if (ref.discountPercent > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ваша скидка: ${ref.discountPercent}%',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '% Пригласите друзей для скидки',
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.monetization_on, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      children: [
                        const TextSpan(text: 'Вы получаете '),
                        TextSpan(
                          text: '20%',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.primary),
                        ),
                        const TextSpan(
                            text: ' на баланс с каждой покупки реферала'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ─── Бонус за реферала ───
          if (ref.bonusAvailable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, size: 20, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'При первом пополнении от 100₽ вы получите +80₽ бонус!',
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          if (ref.bonusReceived)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 20, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Бонус +80₽ получен!',
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),

          // ─── Ввод реферального кода ───
          if (!ref.hasReferrer) ...[
            Row(
              children: [
                Icon(Icons.person_add, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text('У вас есть реферальный код?',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.input, size: 18),
                label: const Text('Ввести реферальный код'),
                onPressed: () => _showReferralCodeDialog(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Уровни ───
          Row(
            children: [
              Icon(Icons.emoji_events, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text('Уровни',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 8),
          ...ref.tiers.map((t) {
            final isActive = ref.confirmedCount >= t.count;
            final isNext = !isActive &&
                (ref.tiers.where((x) => ref.confirmedCount < x.count).firstOrNull == t);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: isNext
                    ? Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? cs.primary.withValues(alpha: 0.25)
                          : cs.surfaceContainerHighest,
                    ),
                    child: Icon(
                      isActive
                          ? Icons.arrow_circle_right
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: isActive ? cs.primary : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${t.count} рефералов',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? cs.primary : null,
                      ),
                    ),
                  ),
                  Text(
                    '${t.discount}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),

          // ─── Нижняя статистика ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Приглашено: ${ref.confirmedCount}',
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5)),
              ),
              if (ref.nextTier != null)
                Text(
                  'Следующий: ${ref.nextTier!['needed'] ?? ref.nextTier!['count']} '
                  '(ещё ${ref.nextTier!['remaining'] ?? ref.nextTier!['needed']})',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5)),
                ),
            ],
          ),
          // Прогресс бар до следующего уровня
          if (ref.nextTier != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _calcReferralProgress(ref),
                minHeight: 4,
                backgroundColor: cs.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
          ],
        ],
      ],
    );
  }

  double _calcReferralProgress(ReferralInfo ref) {
    if (ref.nextTier == null) return 1.0;
    final needed = (ref.nextTier!['needed'] as num?)?.toInt() ??
        (ref.nextTier!['count'] as num?)?.toInt() ??
        5;
    final remaining = (ref.nextTier!['remaining'] as num?)?.toInt() ?? needed;
    final done = needed - remaining;
    if (needed <= 0) return 1.0;
    return (done / needed).clamp(0.0, 1.0);
  }

  void _showReferralCodeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        bool isApplying = false;
        String? errorText;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Реферальный код'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Введите код друга, чтобы получить +80₽ при первом пополнении от 100₽.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Введите код',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: isApplying
                      ? null
                      : () async {
                          final code = controller.text.trim();
                          if (code.isEmpty) {
                            setDialogState(() => errorText = 'Введите код');
                            return;
                          }
                          setDialogState(() {
                            isApplying = true;
                            errorText = null;
                          });
                          final result = await PurchaseService.instance
                              .applyReferralCode(code);
                          if (!ctx.mounted) return;
                          if (result.success) {
                            Navigator.of(ctx).pop();
                            _showSnack(
                              result.message ?? 'Реферальный код применён!',
                              color: Colors.green,
                            );
                            _loadData();
                          } else {
                            setDialogState(() {
                              isApplying = false;
                              errorText = result.error ?? 'Ошибка';
                            });
                          }
                        },
                  child: isApplying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Применить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────── Устройства ───────────────────

  Widget _buildDevicesCard(ColorScheme cs) {
    final dr = _devicesResult;
    final hasDevices = dr != null && dr.success;

    return _card(
      cs,
      icon: Icons.devices,
      title: 'Устройства',
      children: [
        if (!hasDevices)
          Text(
            dr?.error ?? 'Не удалось загрузить устройства',
            style: const TextStyle(color: Colors.grey),
          )
        else ...[
          // Прогрессбар лимита
          _buildDeviceLimitBar(cs, dr.count, dr.limit),
          const SizedBox(height: 8),
          Text(
            'Подключено ${dr.count} из ${dr.limit}',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),

          if (dr.devices.isEmpty)
            const Text('Нет подключённых устройств',
                style: TextStyle(color: Colors.grey))
          else
            ...dr.devices.map((d) => _buildDeviceItem(cs, d)),

          // Забаненные устройства
          if (_bannedDevices.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Заблокированные устройства (${_bannedDevices.length})',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ..._bannedDevices.map((b) => _buildBannedDeviceItem(cs, b)),
          ],
        ],
      ],
    );
  }

  Widget _buildDeviceLimitBar(ColorScheme cs, int count, int limit) {
    final ratio = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
    Color barColor;
    if (ratio >= 1.0) {
      barColor = Colors.red;
    } else if (ratio >= 0.8) {
      barColor = Colors.orange;
    } else {
      barColor = cs.primary;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 8,
        backgroundColor: cs.surfaceContainerLow,
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
      ),
    );
  }

  Widget _buildDeviceItem(ColorScheme cs, VpnDevice d) {
    final osLower = d.os.toLowerCase();
    final isPhone = osLower.contains('android') || osLower.contains('ios');
    final icon = isPhone ? Icons.phone_android : Icons.laptop;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.model != '—' ? d.model : d.os,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  '${d.os} ${d.osVer}'.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  d.hwid,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.block, color: Colors.red, size: 22),
            tooltip: 'Заблокировать',
            onPressed: () => _confirmBanDevice(d),
          ),
        ],
      ),
    );
  }

  Widget _buildBannedDeviceItem(ColorScheme cs, BannedDevice b) {
    final name = b.deviceModel.isNotEmpty
        ? b.deviceModel
        : (b.deviceOs.isNotEmpty ? b.deviceOs : 'Устройство');
    final hwidShort =
        b.hwid.length > 12 ? '${b.hwid.substring(0, 12)}...' : b.hwid;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: cs.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.error)),
                Text(hwidShort,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.4))),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _confirmUnbanDevice(b),
            child: const Text('Разбан', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _confirmBanDevice(VpnDevice d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заблокировать устройство?'),
        content: Text(
          'Устройство «${d.model}» будет заблокировано. '
          'Все VPN-соединения будут разорваны, подписка будет обновлена. '
          'Легитимным устройствам потребуется обновить подписку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _doBanDevice(d);
            },
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _doBanDevice(VpnDevice d) async {
    _showSnack('Блокировка устройства...');
    final result = await PurchaseService.instance.banDevice(
      d.hwidFull,
      os: d.os,
      model: d.model,
    );
    if (!mounted) return;

    if (result.success) {
      if (result.newSubscriptionUrl != null &&
          result.newSubscriptionUrl!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            FoxConfig.keySubscriptionUrl, result.newSubscriptionUrl!);
      }
      _showSnack(result.message ?? 'Устройство заблокировано',
          color: Colors.green);
      _loadData();
    } else {
      _showSnack(result.error ?? 'Ошибка блокировки', color: Colors.red);
    }
  }

  void _confirmUnbanDevice(BannedDevice b) {
    final name = b.deviceModel.isNotEmpty ? b.deviceModel : 'устройство';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Разблокировать устройство?'),
        content: Text('Устройство «$name» будет разблокировано.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _doUnbanDevice(b);
            },
            child: const Text('Разблокировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _doUnbanDevice(BannedDevice b) async {
    _showSnack('Разблокировка...');
    final result = await PurchaseService.instance.unbanDevice(b.hwid);
    if (!mounted) return;

    if (result.success) {
      _showSnack(result.message ?? 'Устройство разблокировано',
          color: Colors.green);
      _loadData();
    } else {
      _showSnack(result.error ?? 'Ошибка разблокировки', color: Colors.red);
    }
  }

  // ─────────────────── Привязка Telegram ───────────────────

  Widget _buildTelegramCard(ColorScheme cs) {
    final acc = _accountInfo;
    final linked = acc?.telegramLinked ?? false;
    final tgName = acc?.telegramName ?? '';

    return _card(
      cs,
      icon: Icons.telegram,
      title: 'Привязка Telegram',
      children: [
        if (linked) ...[
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tgName.isNotEmpty
                      ? 'Telegram привязан: $tgName'
                      : 'Telegram привязан',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Отвязать Telegram'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => _confirmUnlinkTelegram(),
            ),
          ),
        ] else ...[
          const Text(
            'Привяжите Telegram для управления подпиской через бота.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.vpn_key, size: 18),
              label: const Text('Получить код привязки'),
              onPressed: () => _generateTelegramCode(),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _generateTelegramCode() async {
    final result = await PurchaseService.instance.generateTelegramLinkCode();
    if (!mounted) return;

    if (!result.success) {
      _showSnack(result.error ?? 'Ошибка', color: Colors.red);
      return;
    }

    final code = result.code ?? '';
    final botUsername =
        result.botUsername ?? FoxConfig.telegramBotUsername;
    final deepLink = 'https://t.me/$botUsername?start=link_$code';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Код привязки Telegram'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ваш код привязки:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Нажмите «Открыть бота» и отправьте ему эту ссылку.\n'
              'Код действителен 5 минут.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Открыть бота'),
            onPressed: () {
              launchUrl(
                Uri.parse(deepLink),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmUnlinkTelegram() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать Telegram?'),
        content: const Text(
            'Вы больше не сможете управлять подпиской через бота.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await PurchaseService.instance.unlinkTelegram();
              if (mounted) {
                if (ok) {
                  _showSnack('Telegram отвязан', color: Colors.green);
                  _loadData();
                } else {
                  _showSnack('Ошибка отвязки', color: Colors.red);
                }
              }
            },
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );
  }

  // ─────────────────── Подписка ───────────────────

  Widget _buildPurchaseCard(ColorScheme cs) {
    return _card(
      cs,
      icon: Icons.shopping_cart,
      title: 'Подписка',
      children: [
        const Text(
          'Продлите или купите новую подписку.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.card_giftcard, size: 18),
            label: const Text('Продлить подписку'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PurchasePage()),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────── Промокод ───────────────────

  Widget _buildPromoCard(ColorScheme cs) {
    return _card(
      cs,
      icon: Icons.confirmation_number,
      title: 'Промокод',
      children: [
        const Text(
          'Введите промокод для получения бонусов.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.redeem, size: 18),
            label: const Text('Ввести промокод'),
            onPressed: () => _showPromoCodeDialog(),
          ),
        ),
      ],
    );
  }

  void _showPromoCodeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        bool isApplying = false;
        String? errorText;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Ввести промокод'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Введите промокод',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: isApplying
                      ? null
                      : () async {
                          final code = controller.text.trim();
                          if (code.isEmpty) {
                            setDialogState(
                                () => errorText = 'Введите промокод');
                            return;
                          }
                          setDialogState(() {
                            isApplying = true;
                            errorText = null;
                          });
                          final result = await PurchaseService.instance
                              .applyPromoCode(code);
                          if (!ctx.mounted) return;
                          if (result.success) {
                            Navigator.of(ctx).pop();
                            _showSnack(
                              result.message ?? 'Промокод применён!',
                              color: Colors.green,
                            );
                            _loadData();
                          } else {
                            setDialogState(() {
                              isApplying = false;
                              errorText = result.error ?? 'Ошибка';
                            });
                          }
                        },
                  child: isApplying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Применить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────── Хелперы ───────────────────

  Widget _card(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
