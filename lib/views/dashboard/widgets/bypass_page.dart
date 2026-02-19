import 'dart:async';
import 'dart:convert';

import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/models/models.dart';
import 'package:foxcloud/plugins/app.dart';
import 'package:foxcloud/providers/providers.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Predefined site category with a name and list of domain patterns.
class SiteCategory {
  final String name;
  final IconData icon;
  final List<String> domains;

  const SiteCategory({
    required this.name,
    required this.icon,
    required this.domains,
  });
}

/// Predefined Russian site categories that users might want to bypass VPN for.
const List<SiteCategory> predefinedSiteCategories = [
  SiteCategory(
    name: 'Российские сайты',
    icon: Icons.language,
    domains: [
      '*yandex.ru',
      '*yandex.net',
      '*ya.ru',
      '*mail.ru',
      '*rambler.ru',
      '*ok.ru',
      '*sberbank.ru',
      '*tinkoff.ru',
      '*gazprom.ru',
      '*ria.ru',
      '*rbc.ru',
      '*lenta.ru',
      '*kinopoisk.ru',
      '*avito.ru',
      '*drom.ru',
      '*2gis.ru',
    ],
  ),
  SiteCategory(
    name: 'Сайты госорганов РФ',
    icon: Icons.account_balance,
    domains: [
      '*gosuslugi.ru',
      '*nalog.ru',
      '*mos.ru',
      '*gov.ru',
      '*kremlin.ru',
      '*pfr.gov.ru',
      '*rosreestr.gov.ru',
      '*fss.ru',
      '*cbr.ru',
      '*mvd.ru',
    ],
  ),
  SiteCategory(
    name: 'VK',
    icon: Icons.people,
    domains: [
      '*vk.com',
      '*vk.me',
      '*vkontakte.ru',
      '*vk.cc',
      '*vk-cdn.net',
      '*userapi.com',
      '*vkuservideo.net',
    ],
  ),
  SiteCategory(
    name: 'TikTok',
    icon: Icons.music_note,
    domains: [
      '*tiktok.com',
      '*tiktokcdn.com',
      '*tiktokv.com',
      '*musical.ly',
      '*bytedance.com',
      '*bytecdn.cn',
      '*ibytedtos.com',
    ],
  ),
  SiteCategory(
    name: 'Сервисы Яндекса',
    icon: Icons.search,
    domains: [
      '*yandex.ru',
      '*yandex.net',
      '*yandex.com',
      '*ya.ru',
      '*yastatic.net',
      '*yandex-team.ru',
      '*kinopoisk.ru',
      '*music.yandex.ru',
      '*disk.yandex.ru',
      '*market.yandex.ru',
      '*delivery-club.ru',
      '*eda.yandex.ru',
      '*taxi.yandex.ru',
      '*yandex.go',
    ],
  ),
  SiteCategory(
    name: 'Ozon',
    icon: Icons.shopping_bag,
    domains: [
      '*ozon.ru',
      '*ozon.travel',
      '*ozonbank.ru',
      '*cdn.ozone.ru',
    ],
  ),
  SiteCategory(
    name: 'Wildberries',
    icon: Icons.shopping_cart,
    domains: [
      '*wildberries.ru',
      '*wb.ru',
      '*wbstatic.net',
      '*wbbasket.ru',
      '*wbx-content.ru',
    ],
  ),
];

/// Full-screen page showing bypass settings in two tabs: Apps and Sites.
class BypassPage extends ConsumerStatefulWidget {
  const BypassPage({super.key});

  @override
  ConsumerState<BypassPage> createState() => _BypassPageState();
}

class _BypassPageState extends ConsumerState<BypassPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _packagesCompleter = Completer();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _packagesCompleter.complete(globalState.appController.getPackages());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Что работает без VPN?'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Приложения'),
            Tab(text: 'Сайты'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AppsTab(packagesCompleter: _packagesCompleter),
          const _SitesTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _AppsTab extends ConsumerStatefulWidget {
  final Completer packagesCompleter;
  const _AppsTab({required this.packagesCompleter});

  @override
  ConsumerState<_AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends ConsumerState<_AppsTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSystemApps = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleApp(String packageName, bool bypass) {
    ref.read(vpnSettingProvider.notifier).updateState((state) {
      final currentRejectList = List<String>.from(state.accessControl.rejectList);
      if (bypass) {
        if (!currentRejectList.contains(packageName)) {
          currentRejectList.add(packageName);
        }
      } else {
        currentRejectList.remove(packageName);
      }
      return state.copyWith.accessControl(
        rejectList: currentRejectList,
        // Ensure access control is enabled and in rejectSelected mode
        enable: true,
        mode: AccessControlMode.rejectSelected,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(packageListSelectorStateProvider);
    final accessControl = state.accessControl;
    final rejectList = accessControl.rejectList;
    // Get all packages (including system) or only user apps
    final allPackages = state.packages;
    final packages = _showSystemApps
        ? allPackages
            .where((item) => accessControl.isFilterNonInternetApp ? item.internet == true : true)
            .toList()
        : state.list;

    // Filter by search
    final filteredPackages = _searchQuery.isEmpty
        ? packages
        : packages.where((p) =>
            p.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            p.packageName.toLowerCase().contains(_searchQuery.toLowerCase()),
          ).toList();

    // Sort: bypassed apps first
    final sorted = List<Package>.from(filteredPackages)
      ..sort((a, b) {
        final aSelected = rejectList.contains(a.packageName);
        final bSelected = rejectList.contains(b.packageName);
        if (aSelected && !bSelected) return -1;
        if (!aSelected && bSelected) return 1;
        return a.label.compareTo(b.label);
      });

    return Column(
      children: [
        // Counter + search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${rejectList.length} / ${packages.length}',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'приложений без VPN',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // System apps toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Row(
            children: [
              Icon(Icons.android, size: 18, color: context.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Системные приложения',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                value: _showSystemApps,
                onChanged: (val) => setState(() => _showSystemApps = val),
              ),
            ],
          ),
        ),

        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск приложения...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // App list
        Expanded(
          child: FutureBuilder(
            future: widget.packagesCompleter.future,
            builder: (_, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (sorted.isEmpty) {
                return Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'Ничего не найдено'
                        : 'Нет приложений',
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: sorted.length,
                itemExtent: 64,
                itemBuilder: (_, index) {
                  final package = sorted[index];
                  final isBypassed = rejectList.contains(package.packageName);
                  return _AppTile(
                    package: package,
                    isBypassed: isBypassed,
                    onToggle: (val) => _toggleApp(package.packageName, val),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  final Package package;
  final bool isBypassed;
  final ValueChanged<bool> onToggle;

  const _AppTile({
    required this.package,
    required this.isBypassed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: FutureBuilder<ImageProvider?>(
          future: app?.getPackageIcon(package.packageName),
          builder: (_, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return Icon(
                Icons.android,
                size: 36,
                color: context.colorScheme.onSurfaceVariant,
              );
            }
            return Image(
              image: snapshot.data!,
              width: 40,
              height: 40,
              gaplessPlayback: true,
            );
          },
        ),
      ),
      title: Text(
        package.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        package.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Switch(
        value: isBypassed,
        onChanged: (val) => onToggle(val),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SITES TAB
// ─────────────────────────────────────────────────────────────────────────────

/// Stored custom category model.
class _CustomCategory {
  String name;
  List<String> domains;

  _CustomCategory({required this.name, required this.domains});

  Map<String, dynamic> toJson() => {'name': name, 'domains': domains};

  factory _CustomCategory.fromJson(Map<String, dynamic> json) =>
      _CustomCategory(
        name: json['name'] as String? ?? '',
        domains: List<String>.from(json['domains'] as List? ?? []),
      );
}

const _kCustomCategoriesKey = 'fox_custom_bypass_categories';

class _SitesTab extends ConsumerStatefulWidget {
  const _SitesTab();

  @override
  ConsumerState<_SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends ConsumerState<_SitesTab> {
  List<_CustomCategory> _customCategories = [];
  final Set<int> _expandedCustom = {};

  @override
  void initState() {
    super.initState();
    _loadCustomCategories();
  }

  Future<void> _loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCustomCategoriesKey);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List;
        setState(() {
          _customCategories =
              list.map((e) => _CustomCategory.fromJson(e)).toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCustomCategoriesKey,
      json.encode(_customCategories.map((c) => c.toJson()).toList()),
    );
  }

  bool _isCategoryActive(SiteCategory category, List<String> bypassDomains) {
    return category.domains.every((d) => bypassDomains.contains(d));
  }

  bool _isCustomCategoryActive(
      _CustomCategory category, List<String> bypassDomains) {
    if (category.domains.isEmpty) return false;
    return category.domains.every((d) => bypassDomains.contains(d));
  }

  void _togglePredefined(SiteCategory category, bool enable) {
    ref.read(networkSettingProvider.notifier).updateState((state) {
      final current = List<String>.from(state.bypassDomain);
      if (enable) {
        for (final d in category.domains) {
          if (!current.contains(d)) current.add(d);
        }
      } else {
        current.removeWhere((d) => category.domains.contains(d));
      }
      return state.copyWith(bypassDomain: current);
    });
    globalState.appController.applyProfileDebounce();
  }

  void _toggleCustomCategory(int index, bool enable) {
    final category = _customCategories[index];
    ref.read(networkSettingProvider.notifier).updateState((state) {
      final current = List<String>.from(state.bypassDomain);
      if (enable) {
        for (final d in category.domains) {
          if (!current.contains(d)) current.add(d);
        }
      } else {
        current.removeWhere((d) => category.domains.contains(d));
      }
      return state.copyWith(bypassDomain: current);
    });
    globalState.appController.applyProfileDebounce();
  }

  void _toggleDomainInCustom(int catIndex, String domain, bool enable) {
    ref.read(networkSettingProvider.notifier).updateState((state) {
      final current = List<String>.from(state.bypassDomain);
      if (enable) {
        if (!current.contains(domain)) current.add(domain);
      } else {
        current.remove(domain);
      }
      return state.copyWith(bypassDomain: current);
    });
    globalState.appController.applyProfileDebounce();
  }

  void _removeDomainFromCustom(int catIndex, String domain) {
    setState(() {
      _customCategories[catIndex].domains.remove(domain);
    });
    _saveCustomCategories();
    // Also remove from bypass list
    ref.read(networkSettingProvider.notifier).updateState((state) {
      final current = List<String>.from(state.bypassDomain);
      current.remove(domain);
      return state.copyWith(bypassDomain: current);
    });
    globalState.appController.applyProfileDebounce();
  }

  void _deleteCustomCategory(int index) {
    final domains = _customCategories[index].domains;
    setState(() {
      _customCategories.removeAt(index);
      _expandedCustom.remove(index);
    });
    _saveCustomCategories();
    // Remove all its domains from bypass
    ref.read(networkSettingProvider.notifier).updateState((state) {
      final current = List<String>.from(state.bypassDomain);
      current.removeWhere((d) => domains.contains(d));
      return state.copyWith(bypassDomain: current);
    });
    globalState.appController.applyProfileDebounce();
  }

  void _showCreateCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Название',
            labelText: 'Имя категории',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _customCategories
                      .add(_CustomCategory(name: name, domains: []));
                });
                _saveCustomCategories();
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showAddDomainDialog(int catIndex) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить адрес'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '*example.com',
            labelText: 'Домен',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final domain = controller.text.trim();
              if (domain.isNotEmpty) {
                setState(() {
                  if (!_customCategories[catIndex].domains.contains(domain)) {
                    _customCategories[catIndex].domains.add(domain);
                  }
                });
                _saveCustomCategories();
                // Also add to bypass list
                ref
                    .read(networkSettingProvider.notifier)
                    .updateState((state) {
                  final current = List<String>.from(state.bypassDomain);
                  if (!current.contains(domain)) current.add(domain);
                  return state.copyWith(bypassDomain: current);
                });
                globalState.appController.applyProfileDebounce();
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bypassDomains = ref.watch(
      networkSettingProvider.select((state) => state.bypassDomain),
    );

    int activeCategoryCount() {
      return predefinedSiteCategories
          .where((c) => _isCategoryActive(c, bypassDomains))
          .length;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Counter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${activeCategoryCount()} / ${predefinedSiteCategories.length}',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'категорий включено',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Predefined categories
        ...predefinedSiteCategories.map((category) {
          final isActive = _isCategoryActive(category, bypassDomains);
          return _SiteCategoryTile(
            category: category,
            isActive: isActive,
            onToggle: (val) => _togglePredefined(category, val),
          );
        }),

        if (_customCategories.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 8),
        ],

        // Custom categories
        ...List.generate(_customCategories.length, (i) {
          final cat = _customCategories[i];
          final isActive = _isCustomCategoryActive(cat, bypassDomains);
          final isExpanded = _expandedCustom.contains(i);
          return _CustomCategorySection(
            category: cat,
            index: i,
            isActive: isActive,
            isExpanded: isExpanded,
            bypassDomains: bypassDomains,
            onToggleCategory: (val) => _toggleCustomCategory(i, val),
            onToggleExpand: () {
              setState(() {
                if (isExpanded) {
                  _expandedCustom.remove(i);
                } else {
                  _expandedCustom.add(i);
                }
              });
            },
            onToggleDomain: (domain, val) =>
                _toggleDomainInCustom(i, domain, val),
            onRemoveDomain: (domain) => _removeDomainFromCustom(i, domain),
            onAddDomain: () => _showAddDomainDialog(i),
            onDeleteCategory: () => _deleteCustomCategory(i),
          );
        }),

        const SizedBox(height: 12),

        // Create new category button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: _showCreateCategoryDialog,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Создать новый список'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

/// Expandable custom category section.
class _CustomCategorySection extends StatelessWidget {
  final _CustomCategory category;
  final int index;
  final bool isActive;
  final bool isExpanded;
  final List<String> bypassDomains;
  final ValueChanged<bool> onToggleCategory;
  final VoidCallback onToggleExpand;
  final void Function(String domain, bool val) onToggleDomain;
  final void Function(String domain) onRemoveDomain;
  final VoidCallback onAddDomain;
  final VoidCallback onDeleteCategory;

  const _CustomCategorySection({
    required this.category,
    required this.index,
    required this.isActive,
    required this.isExpanded,
    required this.bypassDomains,
    required this.onToggleCategory,
    required this.onToggleExpand,
    required this.onToggleDomain,
    required this.onRemoveDomain,
    required this.onAddDomain,
    required this.onDeleteCategory,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount =
        category.domains.where((d) => bypassDomains.contains(d)).length;

    return Column(
      children: [
        // Category header
        ListTile(
          onTap: onToggleExpand,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? context.colorScheme.primaryContainer
                  : context.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 22,
              color: isActive
                  ? context.colorScheme.onPrimaryContainer
                  : context.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            category.name,
            style: context.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            '${category.domains.length} доменов',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount / ${category.domains.length}',
                  style: context.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 24,
              ),
            ],
          ),
        ),

        // Expanded content
        if (isExpanded) ...[
          // Domains within category
          ...category.domains.map((domain) {
            final isDomainActive = bypassDomains.contains(domain);
            return Padding(
              padding: const EdgeInsets.only(left: 24),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.link, size: 18,
                    color: context.colorScheme.onSurfaceVariant),
                title: Text(domain, style: context.textTheme.bodyMedium),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close, size: 18,
                          color: context.colorScheme.onSurfaceVariant),
                      onPressed: () => onRemoveDomain(domain),
                    ),
                    Switch(
                      value: isDomainActive,
                      onChanged: (val) => onToggleDomain(domain, val),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Add domain to category
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAddDomain,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить адрес в категорию'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, size: 20,
                      color: context.colorScheme.error),
                  onPressed: onDeleteCategory,
                  tooltip: 'Удалить категорию',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SiteCategoryTile extends StatelessWidget {
  final SiteCategory category;
  final bool isActive;
  final ValueChanged<bool> onToggle;

  const _SiteCategoryTile({
    required this.category,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? context.colorScheme.primaryContainer
              : context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          category.icon,
          size: 22,
          color: isActive
              ? context.colorScheme.onPrimaryContainer
              : context.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        category.name,
        style: context.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${category.domains.length} доменов',
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Switch(
        value: isActive,
        onChanged: (val) => onToggle(val),
      ),
    );
  }
}
