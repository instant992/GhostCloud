import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/views/purchase/payment_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full purchase flow screen.
///
/// Steps:
///   1. Select a plan
///   2. Enter email
///   3. Pay via YooKassa (opens browser)
///   4. Wait for payment confirmation (auto-poll)
///   5. Return subscription URL
class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});

  /// Shows the purchase page and returns subscription_url on success, or null.
  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const PurchasePage()),
    );
  }

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

enum _Step { loading, plans, email, paying, waitingPayment, success, error }

class _PurchasePageState extends State<PurchasePage> {
  _Step _step = _Step.loading;

  // Plan selection
  List<VpnPlan> _plans = [];
  VpnPlan? _selectedPlan;

  // Email
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  String? _emailError;

  // Payment
  String? _orderId;
  StreamSubscription<PaymentStatusResult>? _pollSub;

  // Result
  String? _subscriptionUrl;
  String? _login;
  String? _password;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    setState(() => _step = _Step.loading);
    final plans = await PurchaseService.instance.getPlans();
    if (!mounted) return;
    if (plans.isEmpty) {
      setState(() {
        _step = _Step.error;
        _errorMessage = 'Не удалось загрузить тарифы. Проверьте соединение.';
      });
      return;
    }
    setState(() {
      _plans = plans;
      _selectedPlan = plans.length > 1 ? plans[1] : plans[0]; // default to first paid plan
      _step = _Step.plans;
    });
  }

  void _onPlanSelected(VpnPlan plan) {
    setState(() => _selectedPlan = plan);
  }

  void _goToEmail() {
    if (_selectedPlan == null) return;
    setState(() => _step = _Step.email);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
  }

  bool _validateEmail(String email) {
    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return pattern.hasMatch(email.trim());
  }

  Future<void> _startPayment() async {
    final email = _emailController.text.trim();
    if (!_validateEmail(email)) {
      setState(() => _emailError = 'Введите корректный email');
      return;
    }
    setState(() {
      _emailError = null;
      _step = _Step.paying;
    });

    final result = await PurchaseService.instance.createPayment(
      email: email,
      planId: _selectedPlan!.id,
    );

    if (!mounted) return;

    if (!result.success || result.confirmationUrl == null) {
      setState(() {
        _step = _Step.error;
        _errorMessage = result.error ?? 'Ошибка создания платежа';
      });
      return;
    }

    _orderId = result.orderId;

    // Open payment page in in-app WebView
    try {
      await PaymentWebView.show(context, result.confirmationUrl!);
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = 'Не удалось открыть страницу оплаты';
      });
      return;
    }

    // Start polling
    setState(() => _step = _Step.waitingPayment);
    _pollSub?.cancel();
    _pollSub = PurchaseService.instance
        .pollPaymentStatus(_orderId!)
        .listen((status) {
      if (!mounted) return;
      if (status.status == PaymentPollStatus.succeeded) {
        // Save credentials locally for auto-login
        if (status.login != null && status.password != null) {
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString(FoxConfig.keySavedLogin, status.login!);
            prefs.setString(FoxConfig.keySavedPassword, status.password!);
          });
        }
        setState(() {
          _step = _Step.success;
          _subscriptionUrl = status.subscriptionUrl;
          _login = status.login;
          _password = status.password;
        });
      } else if (status.status == PaymentPollStatus.canceled) {
        setState(() {
          _step = _Step.error;
          _errorMessage = 'Платёж отменён';
        });
      }
    });
  }

  void _finishWithSubscription() {
    Navigator.of(context).pop(_subscriptionUrl);
  }

  void _finishCancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Купить подписку'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _finishCancel,
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
      _Step.loading => const Center(
          key: ValueKey('loading'),
          child: CircularProgressIndicator(),
        ),
      _Step.plans => _buildPlans(theme, colorScheme),
      _Step.email => _buildEmail(theme, colorScheme),
      _Step.paying => const Center(
          key: ValueKey('paying'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Создаём платёж...'),
            ],
          ),
        ),
      _Step.waitingPayment => _buildWaitingPayment(theme, colorScheme),
      _Step.success => _buildSuccess(theme, colorScheme),
      _Step.error => _buildError(theme, colorScheme),
    };
  }

  // ─── Plan selection ───

  Widget _buildPlans(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('plans'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            'Выберите тариф',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Безлимитный VPN для всех устройств',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: _plans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plan = _plans[index];
                final isSelected = plan.id == _selectedPlan?.id;
                final isTrial = plan.id == 'trial';

                return _PlanCard(
                  plan: plan,
                  isSelected: isSelected,
                  isTrial: isTrial,
                  onTap: () => _onPlanSelected(plan),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _selectedPlan != null ? _goToEmail : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _selectedPlan != null
                    ? 'Далее — ${_selectedPlan!.price} ₽'
                    : 'Выберите тариф',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Email entry ───

  Widget _buildEmail(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('email'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _step = _Step.plans),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Text(
            'Введите email',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'На этот email будут отправлены данные для входа.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _startPayment(),
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'example@mail.com',
              errorText: _emailError,
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Тариф: ${_selectedPlan!.name} — ${_selectedPlan!.price} ₽',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _startPayment,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Оплатить ${_selectedPlan!.price} ₽',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Waiting for payment ───

  Widget _buildWaitingPayment(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('waiting'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Ожидаем оплату...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Завершите оплату в браузере.\nСтраница обновится автоматически.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: _finishCancel,
              child: const Text('Отменить'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Success ───

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
                color: Colors.green.withValues(alpha: 0.15),
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
              'Оплата прошла!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_subscriptionUrl != null && _subscriptionUrl!.isNotEmpty) ...[
              Text(
                'Подписка будет добавлена автоматически.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Text(
                'Подписка создаётся — данные придут на email.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_login != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Логин', _login!, theme),
                    if (_password != null) ...[
                      const SizedBox(height: 8),
                      _infoRow('Пароль', _password!, theme),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Сохраните эти данные — они нужны для входа на сайте',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _finishWithSubscription,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _subscriptionUrl != null ? 'Подключить VPN' : 'Готово',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Row(
      children: [
        Text('$label: ',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ─── Error ───

  Widget _buildError(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Произошла ошибка',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadPlans,
              child: const Text('Попробовать снова'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _finishCancel,
              child: const Text('Назад'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Plan card widget ───

class _PlanCard extends StatelessWidget {
  final VpnPlan plan;
  final bool isSelected;
  final bool isTrial;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isTrial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surface,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Plan icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isTrial
                      ? Colors.orange.withValues(alpha: 0.15)
                      : colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isTrial ? Icons.bolt : Icons.shield_outlined,
                  color: isTrial ? Colors.orange : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),

              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isTrial)
                      Text(
                        'Попробуйте бесплатно',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                  ],
                ),
              ),

              // Price
              Text(
                '${plan.price} ₽',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? colorScheme.primary : null,
                ),
              ),

              // Check
              const SizedBox(width: 12),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isSelected ? 1.0 : 0.0,
                child: Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
