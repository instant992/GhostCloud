import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/models/models.dart';
import 'package:foxcloud/views/views.dart';
import 'package:flutter/material.dart';

class Navigation {

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }

  Navigation._internal();
  static Navigation? _instance;

  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) => [
      const NavigationItem(
        keep: false,
        icon: Icon(Icons.space_dashboard),
        label: PageLabel.dashboard,
        view: DashboardView(
          key: GlobalObjectKey(PageLabel.dashboard),
        ),
      ),
      const NavigationItem(
        icon: Icon(Icons.card_membership),
        label: PageLabel.subscription,
        view: SubscriptionView(
          key: GlobalObjectKey(PageLabel.subscription),
        ),
      ),
      NavigationItem(
        icon: const Icon(Icons.article),
        label: PageLabel.proxies,
        view: const ProxiesView(
          key: GlobalObjectKey(
            PageLabel.proxies,
          ),
        ),
        modes: hasProxies
            ? [NavigationItemMode.desktop]
            : [],
      ),
      const NavigationItem(
        icon: Icon(Icons.folder),
        label: PageLabel.profiles,
        view: ProfilesView(
          key: GlobalObjectKey(
            PageLabel.profiles,
          ),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.more],
      ),
      const NavigationItem(
        icon: Icon(Icons.view_timeline),
        label: PageLabel.requests,
        view: RequestsView(
          key: GlobalObjectKey(
            PageLabel.requests,
          ),
        ),
        description: "requestsDesc",
        modes: [NavigationItemMode.desktop, NavigationItemMode.more],
      ),
      const NavigationItem(
        icon: Icon(Icons.ballot),
        label: PageLabel.connections,
        view: ConnectionsView(
          key: GlobalObjectKey(
            PageLabel.connections,
          ),
        ),
        description: "connectionsDesc",
        modes: [NavigationItemMode.desktop, NavigationItemMode.more],
      ),
      const NavigationItem(
        icon: Icon(Icons.storage),
        label: PageLabel.resources,
        description: "resourcesDesc",
        view: ResourcesView(
          key: GlobalObjectKey(
            PageLabel.resources,
          ),
        ),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        icon: const Icon(Icons.adb),
        label: PageLabel.logs,
        view: const LogsView(
          key: GlobalObjectKey(
            PageLabel.logs,
          ),
        ),
        description: "logsDesc",
        modes: openLogs
            ? [NavigationItemMode.desktop, NavigationItemMode.more]
            : [],
      ),
      const NavigationItem(
        icon: Icon(Icons.support_agent),
        label: PageLabel.support,
        view: SupportChatView(
          key: GlobalObjectKey(PageLabel.support),
        ),
        modes: [NavigationItemMode.mobile],
      ),
      const NavigationItem(
        icon: Icon(Icons.construction),
        label: PageLabel.tools,
        view: ToolsView(
          key: GlobalObjectKey(
            PageLabel.tools,
          ),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
    ];
}

final navigation = Navigation();
