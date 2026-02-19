import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/providers/auth.dart';
import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/views/purchase/plans_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Login screen shown before the main app.
/// Offers Telegram-based authentication.
class FoxLoginView extends ConsumerWidget {
  const FoxLoginView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(foxAuthProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
                  'assets/images/icon.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 24),

                // App name
                Text(
                  'GhostCloud',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Безопасный VPN для всех устройств',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Auth state UI
                _buildAuthContent(context, ref, authState),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthContent(
    BuildContext context,
    WidgetRef ref,
    FoxAuthState authState,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (authState.status) {
      case FoxAuthStatus.checking:
        return const Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Проверка авторизации...'),
          ],
        );

      case FoxAuthStatus.unauthenticated:
        return Column(
          children: [
            // Buy subscription — main action
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () async {
                  final subUrl = await PurchasePage.show(context);
                  if (subUrl != null && subUrl.isNotEmpty && context.mounted) {
                    ref.read(foxAuthProvider.notifier).skipAuthWithSubscription(subUrl);
                  }
                },
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text(
                  'Купить подписку',
                  style: TextStyle(fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Login by credentials (auto-login if purchased on this device)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Try auto-login with saved credentials first
                  final prefs = await SharedPreferences.getInstance();
                  final savedLogin = prefs.getString(FoxConfig.keySavedLogin);
                  final savedPassword = prefs.getString(FoxConfig.keySavedPassword);

                  if (savedLogin != null && savedPassword != null && context.mounted) {
                    // Show loading indicator
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    final result = await PurchaseService.instance.loginWithCredentials(
                      login: savedLogin,
                      password: savedPassword,
                    );

                    if (context.mounted) Navigator.of(context).pop(); // close loading

                    if (result.success && result.subscriptionUrl != null && context.mounted) {
                      ref.read(foxAuthProvider.notifier).skipAuthWithSubscription(result.subscriptionUrl!);
                      return;
                    }
                  }

                  // No saved credentials or auto-login failed — show manual dialog
                  if (!context.mounted) return;
                  final subUrl = await _showLoginDialog(context);
                  if (subUrl != null && subUrl.isNotEmpty && context.mounted) {
                    ref.read(foxAuthProvider.notifier).skipAuthWithSubscription(subUrl);
                  }
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text(
                  'Войти по логину',
                  style: TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );

      case FoxAuthStatus.waitingForTelegram:
        // No longer used — treat as unauthenticated
        return const SizedBox.shrink();

      case FoxAuthStatus.error:
        return Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              authState.errorMessage ?? 'Произошла ошибка',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(foxAuthProvider.notifier).cancelAuth();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Попробовать снова'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );

      case FoxAuthStatus.authenticated:
        // Should not show — app navigates away
        return const SizedBox.shrink();
    }
  }

  /// Show manual login/password dialog.
  Future<String?> _showLoginDialog(BuildContext context) async {
    String? resultUrl;
    final loginCtl = TextEditingController();
    final passCtl = TextEditingController();

    // Pre-fill saved credentials if available
    final prefs = await SharedPreferences.getInstance();
    final savedLogin = prefs.getString(FoxConfig.keySavedLogin);
    final savedPass = prefs.getString(FoxConfig.keySavedPassword);
    if (savedLogin != null) loginCtl.text = savedLogin;
    if (savedPass != null) passCtl.text = savedPass;

    if (!context.mounted) return null;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool loading = false;
        String? error;
        bool obscure = true;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Вход по логину'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Введите логин и пароль, полученные после покупки.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: loginCtl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Логин или email',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtl,
                      obscureText: obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {},
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscure = !obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (error != null) ...[const SizedBox(height: 12), Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13))],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: loading ? null : () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final l = loginCtl.text.trim();
                          final p = passCtl.text.trim();
                          if (l.isEmpty || p.isEmpty) {
                            setDialogState(() => error = 'Введите логин и пароль');
                            return;
                          }
                          setDialogState(() { loading = true; error = null; });
                          final res = await PurchaseService.instance.loginWithCredentials(login: l, password: p);
                          if (!ctx.mounted) return;
                          if (res.success && res.subscriptionUrl != null) {
                            // Save credentials for future auto-login
                            prefs.setString(FoxConfig.keySavedLogin, l);
                            prefs.setString(FoxConfig.keySavedPassword, p);
                            resultUrl = res.subscriptionUrl;
                            Navigator.of(ctx).pop();
                          } else {
                            setDialogState(() { loading = false; error = res.error ?? 'Не удалось войти'; });
                          }
                        },
                  child: loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Войти'),
                ),
              ],
            );
          },
        );
      },
    );
    loginCtl.dispose();
    passCtl.dispose();
    return resultUrl;
  }
}
