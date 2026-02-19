import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/providers/providers.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bypass_page.dart';

/// Dashboard widget — compact card showing "Что работает без VPN?"
/// with a counter badge and tap-to-open behavior.
class BypassWidget extends ConsumerWidget {
  const BypassWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Count bypassed apps
    final accessControl = ref.watch(
      vpnSettingProvider.select((s) => s.accessControl),
    );
    final rejectCount = accessControl.rejectList.length;

    // Count bypassed site categories
    final bypassDomains = ref.watch(
      networkSettingProvider.select((s) => s.bypassDomain),
    );
    int activeSiteCategories = 0;
    for (final cat in predefinedSiteCategories) {
      if (cat.domains.every((d) => bypassDomains.contains(d))) {
        activeSiteCategories++;
      }
    }

    // Total packages count
    final totalPackages = ref.watch(
      packageListSelectorStateProvider.select((s) => s.packages.length),
    );

    return CommonCard(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProviderScope(
              parent: ProviderScope.containerOf(context),
              child: const BypassPage(),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 22,
                color: context.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Что работает без VPN?',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$rejectCount приложений · $activeSiteCategories категорий сайтов',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Counter badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$rejectCount / $totalPackages',
                style: context.textTheme.labelMedium?.copyWith(
                  color: context.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
