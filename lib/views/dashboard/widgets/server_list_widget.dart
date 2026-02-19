import 'dart:convert';
import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/models/common.dart';
import 'package:foxcloud/providers/providers.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_selection_page.dart';

/// Dashboard widget — compact card showing current server selection
/// with a "Выбрать сервер" button that opens the full server selection page.
class ServerListWidget extends ConsumerWidget {
  const ServerListWidget({super.key});

  String? _decodeBase64IfNeeded(String? value) {
    if (value == null || value.isEmpty) return value;
    try {
      return utf8.decode(base64.decode(value));
    } catch (e) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const SizedBox.shrink();

    final serverInfoGroupName = _decodeBase64IfNeeded(
      profile.providerHeaders['foxcloud-serverinfo'],
    );

    final groups = ref.watch(currentGroupsStateProvider).value;

    Group? targetGroup;
    if (serverInfoGroupName != null && serverInfoGroupName.isNotEmpty) {
      targetGroup = groups.getGroup(serverInfoGroupName);
    }
    targetGroup ??=
        groups.where((g) => g.type == GroupType.Selector).firstOrNull;

    if (targetGroup == null || targetGroup.all.isEmpty) {
      return const SizedBox.shrink();
    }

    final group = targetGroup;

    // Determine what's currently selected
    final selectedName =
        ref.watch(getSelectedProxyNameProvider(group.name));
    final isAutoSelect = group.type == GroupType.URLTest &&
        (selectedName == null || selectedName.isEmpty);
    final displayName = isAutoSelect
        ? 'Авто выбор'
        : removeFlagFromProxy(selectedName ?? group.now ?? '');
    final flag = isAutoSelect
        ? null
        : extractFlagFromProxy(selectedName ?? group.now ?? '');

    return CommonCard(
      onPressed: null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current selection display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isAutoSelect)
                  Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: context.colorScheme.primary,
                  )
                else if (flag != null)
                  Text(
                    flag,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.0,
                      fontFamily: FontFamily.twEmoji.value,
                    ),
                  )
                else
                  Icon(
                    Icons.dns_rounded,
                    size: 20,
                    color: context.colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    displayName,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Subtitle
            Text(
              'Выбранная локация',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 12),

            // "Выбрать сервер" button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: ServerSelectionPage(group: group),
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  side: BorderSide(
                    color: context.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dns_rounded,
                      size: 18,
                      color: context.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Выбрать сервер',
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.colorScheme.onSurface,
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
            ),
          ],
        ),
      ),
    );
  }
}
