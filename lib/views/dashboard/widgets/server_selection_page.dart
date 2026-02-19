import 'dart:convert';
import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/models/common.dart';
import 'package:foxcloud/providers/providers.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/views/proxies/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen server selection page with tabs for "Основные" and "LTE".
class ServerSelectionPage extends ConsumerStatefulWidget {
  const ServerSelectionPage({
    super.key,
    required this.group,
  });

  final Group group;

  @override
  ConsumerState<ServerSelectionPage> createState() =>
      _ServerSelectionPageState();
}

class _ServerSelectionPageState extends ConsumerState<ServerSelectionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late List<Proxy> _mainProxies;
  late List<Proxy> _lteProxies;
  late bool _hasLte;

  @override
  void initState() {
    super.initState();
    _splitProxies();
    _tabController = TabController(
      length: _hasLte ? 2 : 1,
      vsync: this,
    );
  }

  void _splitProxies() {
    _mainProxies = [];
    _lteProxies = [];

    for (final proxy in widget.group.all) {
      if (proxy.name.toLowerCase().contains('lte')) {
        _lteProxies.add(proxy);
      } else {
        _mainProxies.add(proxy);
      }
    }
    _hasLte = _lteProxies.isNotEmpty;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-read the group from providers to get live updates (selected proxy, etc.)
    final liveGroups = ref.watch(currentGroupsStateProvider).value;
    final liveGroup = liveGroups.getGroup(widget.group.name) ?? widget.group;

    // Re-split in case proxies changed
    final mainProxies = <Proxy>[];
    final lteProxies = <Proxy>[];
    for (final proxy in liveGroup.all) {
      if (proxy.name.toLowerCase().contains('lte')) {
        lteProxies.add(proxy);
      } else {
        mainProxies.add(proxy);
      }
    }

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Выбери сервер',
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: context.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Confirm / done button
          IconButton(
            icon: Icon(
              Icons.done_all_rounded,
              color: context.colorScheme.primary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        bottom: lteProxies.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildTabBar(context),
              )
            : null,
      ),
      body: lteProxies.isNotEmpty
          ? TabBarView(
              controller: _tabController,
              children: [
                _ServerListSection(
                  group: liveGroup,
                  proxies: mainProxies,
                  label: 'Основные',
                ),
                _ServerListSection(
                  group: liveGroup,
                  proxies: lteProxies,
                  label: 'LTE',
                ),
              ],
            )
          : _ServerListSection(
              group: liveGroup,
              proxies: mainProxies,
              label: 'Локации',
            ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              context.colorScheme.primary.withValues(alpha: 0.8),
              context.colorScheme.primary.withValues(alpha: 0.6),
            ],
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: context.colorScheme.onPrimary,
        unselectedLabelColor: context.colorScheme.onSurfaceVariant,
        labelStyle: context.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'Основные'),
          Tab(text: 'LTE'),
        ],
      ),
    );
  }
}

/// Section that shows a scrollable list of servers with a header.
class _ServerListSection extends ConsumerWidget {
  const _ServerListSection({
    required this.group,
    required this.proxies,
    required this.label,
  });

  final Group group;
  final List<Proxy> proxies;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (proxies.isEmpty) {
      return Center(
        child: Text(
          'Нет серверов',
          style: context.textTheme.bodyLarge?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Text(
                'Локации',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Test delay button
              TextButton.icon(
                onPressed: () => delayTest(proxies, group.testUrl),
                icon: Icon(Icons.speed, size: 16, color: context.colorScheme.primary),
                label: Text(
                  appLocalizations.testDelay,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),

        // Server list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: proxies.length,
            itemBuilder: (context, index) {
              return _ServerTile(
                groupName: group.name,
                groupType: group.type,
                proxy: proxies[index],
                testUrl: group.testUrl,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Авто выбор" tile at the top of the server list.
class _AutoSelectTile extends ConsumerWidget {
  const _AutoSelectTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedName = ref.watch(getSelectedProxyNameProvider(group.name));
    // In URLTest mode, empty selectedName means auto-select is active
    final isAutoActive = group.type == GroupType.URLTest &&
        (selectedName == null || selectedName.isEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (group.type.isComputedSelected) {
              // Reset to auto-select
              final appController = globalState.appController;
              appController.updateCurrentSelectedMap(group.name, '');
              appController.changeProxyDebounce(group.name, '');
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: isAutoActive
                  ? LinearGradient(
                      colors: [
                        context.colorScheme.primary.withValues(alpha: 0.15),
                        context.colorScheme.tertiary.withValues(alpha: 0.1),
                      ],
                    )
                  : null,
              color: isAutoActive
                  ? null
                  : context.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: isAutoActive
                  ? Border.all(
                      color: context.colorScheme.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 22,
                  color: isAutoActive
                      ? context.colorScheme.primary
                      : context.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Авто выбор',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isAutoActive
                        ? context.colorScheme.primary
                        : context.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (isAutoActive)
                  Icon(
                    Icons.check_circle,
                    size: 22,
                    color: context.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ──────────────────────────────────────────────────
//  Helpers shared with the dashboard collapsed card
// ──────────────────────────────────────────────────

String? extractFlagFromProxy(String text) {
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length - 1; i++) {
    final first = runes[i];
    final second = runes[i + 1];
    if (first >= 0x1F1E6 &&
        first <= 0x1F1FF &&
        second >= 0x1F1E6 &&
        second <= 0x1F1FF) {
      return String.fromCharCodes([first, second]);
    }
  }
  return null;
}

String removeFlagFromProxy(String text) {
  final runes = text.runes.toList();
  final result = <int>[];
  var i = 0;
  while (i < runes.length) {
    final current = runes[i];
    if (current >= 0x1F1E6 && current <= 0x1F1FF && i + 1 < runes.length) {
      final next = runes[i + 1];
      if (next >= 0x1F1E6 && next <= 0x1F1FF) {
        i += 2;
        continue;
      }
    }
    result.add(current);
    i++;
  }
  return String.fromCharCodes(result).trim();
}


/// Individual server tile used both in the page and in the dashboard list.
class _ServerTile extends ConsumerWidget {
  const _ServerTile({
    required this.groupName,
    required this.groupType,
    required this.proxy,
    required this.testUrl,
  });

  final String groupName;
  final GroupType groupType;
  final Proxy proxy;
  final String? testUrl;

  Future<void> _changeProxy(WidgetRef ref) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    if (isComputedSelected || isSelector) {
      final currentProxyName = ref.read(getProxyNameProvider(groupName));
      final nextProxyName = switch (isComputedSelected) {
        true => currentProxyName == proxy.name ? "" : proxy.name,
        false => proxy.name,
      };
      final appController = globalState.appController;
      appController.updateCurrentSelectedMap(groupName, nextProxyName);
      appController.changeProxyDebounce(groupName, nextProxyName);
      return;
    }
    globalState.showNotifier(appLocalizations.notSelectedTip);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProxyName =
        ref.watch(getSelectedProxyNameProvider(groupName));
    final isSelected = selectedProxyName == proxy.name;

    final flag = extractFlagFromProxy(proxy.name);
    final nameWithoutFlag = removeFlagFromProxy(proxy.name);

    final delay = ref.watch(getDelayProvider(
      proxyName: proxy.name,
      testUrl: testUrl,
    ));

    Color? delayColor;
    String? delayText;
    if (delay != null && delay > 0) {
      delayColor = utils.getDelayColor(delay);
      delayText = '$delay ms';
    } else if (delay != null && delay < 0) {
      delayColor = Colors.red;
      delayText = 'Timeout';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _changeProxy(ref),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? context.colorScheme.primary.withValues(alpha: 0.10)
                  : context.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? context.colorScheme.primary.withValues(alpha: 0.4)
                    : context.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Flag
                Container(
                  width: 42,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: context.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                  ),
                  child: Center(
                    child: flag != null
                        ? Text(
                            flag,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.0,
                              fontFamily: FontFamily.twEmoji.value,
                            ),
                            textAlign: TextAlign.center,
                          )
                        : Icon(
                            Icons.public,
                            size: 20,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Server name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nameWithoutFlag,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? context.colorScheme.primary
                              : context.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Delay badge
                if (delayText != null) ...[
                  const SizedBox(width: 8),
                  _DelayBadge(
                    text: delayText,
                    color: delayColor ?? context.colorScheme.primary,
                  ),
                ],
                // Selected indicator
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: context.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DelayBadge extends StatelessWidget {
  const _DelayBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
