import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/views/purchase/payment_webview.dart';

/// Страница продления подписки с баланса.
///
/// Шаги:
///   1. Выбор тарифа
///   2. Оплата с баланса или пополнение + оплата
///   3. Результат
class RenewPage extends StatefulWidget {
  const RenewPage({super.key});

  /// Открыть страницу продления. Возвращает true если подписка продлена.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RenewPage()),
    );
    return result ?? false;
  }

  @override
  State<RenewPage> createState() => _RenewPageState();
}

enum _RenewStep { loading, plans, processing, topup, success, error }

class _RenewPageState extends State<RenewPage> {
  _RenewStep _step = _RenewStep.loading;

  List<VpnPlan> _plans = [];
  VpnPlan? _selectedPlan;
  UserAccountInfo? _accountInfo;

  // Результат extend при нехватке средств
  ExtendResult? _extendResult;

  // Результат пополнения
  String? _topupOrderId;
  Timer? _topupPollTimer;

  String? _successMessage;
  int? _newBalance;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _topupPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _step = _RenewStep.loading);

    try {
      final results = await Future.wait([
        PurchaseService.instance.getPlans(),
        PurchaseService.instance.getAccountInfo(),
      ]);

      if (!mounted) return;

      final plans = results[0] as List<VpnPlan>;
      final accountInfo = results[1] as UserAccountInfo?;

      if (plans.isEmpty) {
        setState(() {
          _step = _RenewStep.error;
          _errorMessage = 'Не удалось загрузить тарифы';
        });
        return;
      }

      // Убираем trial из списка продления
      final renewPlans = plans.where((p) => p.id != 'trial').toList();

      setState(() {
        _plans = renewPlans;
        _selectedPlan =
            renewPlans.isNotEmpty ? renewPlans[0] : null; // default 1 month
        _accountInfo = accountInfo;
        _step = _RenewStep.plans;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RenewStep.error;
          _errorMessage = 'Ошибка загрузки: $e';
        });
      }
    }
  }

  void _onPlanSelected(VpnPlan plan) {
    setState(() => _selectedPlan = plan);
  }

  Future<void> _extendWithBalance() async {
    if (_selectedPlan == null) return;

    setState(() => _step = _RenewStep.processing);

    final result =
        await PurchaseService.instance.extendWithBalance(_selectedPlan!.id);

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _step = _RenewStep.success;
        _successMessage = result.message ?? 'Подписка продлена!';
        _newBalance = result.balance;
      });
      return;
    }

    if (result.needTopup) {
      setState(() {
        _extendResult = result;
        _step = _RenewStep.plans; // Остаёмся на странице планов, покажем инфо
      });
      // Показываем диалог доплаты
      if (mounted) {
        _showTopupDialog(result);
      }
      return;
    }

    setState(() {
      _step = _RenewStep.error;
      _errorMessage = result.error ?? 'Ошибка продления';
    });
  }

  void _showTopupDialog(ExtendResult result) {
    final needTopup = result.topupAmount ?? 0;
    // Минимум 10₽ для пополнения
    final topupAmount = needTopup < 10 ? 10 : needTopup;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Недостаточно средств'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Тариф: ${result.planName ?? _selectedPlan?.name ?? "—"}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildInfoLine('Стоимость', '${result.price ?? 0}₽'),
            if ((result.discountPercent ?? 0) > 0)
              _buildInfoLine(
                  'Скидка', '${result.discountPercent}%'),
            _buildInfoLine(
                'Ваш баланс', '${result.currentBalance ?? 0}₽'),
            const Divider(height: 16),
            _buildInfoLine(
              'Нужно пополнить',
              '${topupAmount}₽',
              highlight: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _startTopup(topupAmount);
            },
            child: Text('Пополнить на ${topupAmount}₽'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoLine(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? Colors.orange : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startTopup(int amount) async {
    setState(() => _step = _RenewStep.processing);

    final topupResult =
        await PurchaseService.instance.createTopupPayment(amount);

    if (!mounted) return;

    if (!topupResult.success || topupResult.confirmationUrl == null) {
      setState(() {
        _step = _RenewStep.error;
        _errorMessage =
            topupResult.error ?? 'Не удалось создать платёж пополнения';
      });
      return;
    }

    _topupOrderId = topupResult.orderId;

    // Открываем страницу оплаты
    try {
      await PaymentWebView.show(context, topupResult.confirmationUrl!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RenewStep.error;
          _errorMessage = 'Не удалось открыть страницу оплаты';
        });
      }
      return;
    }

    if (!mounted) return;

    // После закрытия WebView — ждём подтверждения пополнения
    setState(() => _step = _RenewStep.topup);
    _startTopupPolling();
  }

  void _startTopupPolling() {
    int attempts = 0;
    const maxAttempts = 60; // 2 минуты по 2 секунды

    _topupPollTimer?.cancel();
    _topupPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      if (attempts > maxAttempts) {
        timer.cancel();
        setState(() {
          _step = _RenewStep.error;
          _errorMessage = 'Время ожидания оплаты истекло';
        });
        return;
      }

      // Проверяем статус пополнения через серверный эндпоинт
      if (_topupOrderId != null) {
        final statusResult = await PurchaseService.instance.checkTopupStatus(_topupOrderId!);
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (statusResult.status == 'succeeded') {
          // Баланс пополнен! Обновляем данные аккаунта и пробуем продлить
          timer.cancel();
          final accountInfo = await PurchaseService.instance.getAccountInfo();
          if (accountInfo != null) {
            _accountInfo = accountInfo;
          }
          await _extendWithBalance();
          return;
        } else if (statusResult.status == 'canceled') {
          timer.cancel();
          setState(() {
            _step = _RenewStep.error;
            _errorMessage = 'Платёж отменён';
          });
          return;
        }
        // pending — продолжаем поллить
      }
    });
  }

  void _finish(bool renewed) {
    Navigator.of(context).pop(renewed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Продлить подписку'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish(false),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildContent(theme, colorScheme),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    return switch (_step) {
      _RenewStep.loading => const Center(
          key: ValueKey('loading'),
          child: CircularProgressIndicator(),
        ),
      _RenewStep.plans => _buildPlans(theme, colorScheme),
      _RenewStep.processing => const Center(
          key: ValueKey('processing'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Обработка...'),
            ],
          ),
        ),
      _RenewStep.topup => _buildWaitingTopup(theme, colorScheme),
      _RenewStep.success => _buildSuccess(theme, colorScheme),
      _RenewStep.error => _buildError(theme, colorScheme),
    };
  }

  // ─── Plan selection ───

  Widget _buildPlans(ThemeData theme, ColorScheme colorScheme) {
    final balance = _accountInfo?.balance ?? 0;

    return Padding(
      key: const ValueKey('plans'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            'Продление подписки',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Баланс
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Ваш баланс: ',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${balance}₽',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.separated(
              itemCount: _plans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plan = _plans[index];
                final isSelected = plan.id == _selectedPlan?.id;
                final canAfford = balance >= plan.price;

                return _RenewPlanCard(
                  plan: plan,
                  isSelected: isSelected,
                  canAfford: canAfford,
                  balance: balance,
                  onTap: () => _onPlanSelected(plan),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          if (_selectedPlan != null) ...[
            // Кнопка оплаты
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _extendWithBalance,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  balance >= _selectedPlan!.price
                      ? 'Оплатить с баланса — ${_selectedPlan!.price}₽'
                      : 'Продлить — ${_selectedPlan!.price}₽',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            if (balance < _selectedPlan!.price && balance > 0) ...[
              const SizedBox(height: 6),
              Text(
                'С баланса спишется ${balance}₽, нужно доплатить ${_selectedPlan!.price - balance}₽',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Ожидание пополнения ───

  Widget _buildWaitingTopup(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('topup'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Ожидаем пополнение баланса...',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'После подтверждения оплаты подписка будет продлена автоматически',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _topupPollTimer?.cancel();
                setState(() => _step = _RenewStep.plans);
                _loadData(); // refresh balance
              },
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Успех ───

  Widget _buildSuccess(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('success'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _successMessage ?? 'Подписка продлена!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_newBalance != null) ...[
              const SizedBox(height: 12),
              Text(
                'Остаток на балансе: ${_newBalance}₽',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: FilledButton(
                onPressed: () => _finish(true),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Готово'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Ошибка ───

  Widget _buildError(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Произошла ошибка',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadData,
              child: const Text('Попробовать снова'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _finish(false),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Plan card for renewal ───

class _RenewPlanCard extends StatelessWidget {
  const _RenewPlanCard({
    required this.plan,
    required this.isSelected,
    required this.canAfford,
    required this.balance,
    required this.onTap,
  });

  final VpnPlan plan;
  final bool isSelected;
  final bool canAfford;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 2 : 1,
        ),
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
            : colorScheme.surface,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Radio indicator
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  color: isSelected
                      ? colorScheme.primary
                      : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 14),

              // Plan name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!canAfford && balance > 0)
                      Text(
                        'Доплата: ${plan.price - balance}₽',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                  ],
                ),
              ),

              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${plan.price}₽',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (canAfford)
                    Text(
                      '✓ хватает',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
