import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Pointer;

import 'package:animations/animations.dart';
import 'package:dio/dio.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:foxcloud/clash/clash.dart';
import 'package:foxcloud/common/theme.dart';
import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/l10n/l10n.dart';
import 'package:foxcloud/plugins/service.dart';
import 'package:foxcloud/widgets/dialog.dart';
import 'package:foxcloud/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:material_color_utilities/palettes/core_palette.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'controller.dart';
import 'models/models.dart';

typedef UpdateTasks = List<FutureOr Function()>;

class GlobalState {

  factory GlobalState() {
    _instance ??= GlobalState._internal();
    return _instance!;
  }

  GlobalState._internal();
  static GlobalState? _instance;
  Map<CacheTag, double> cacheScrollPosition = {};
  Map<CacheTag, FixedMap<String, double>> cacheHeightMap = {};
  bool isService = false;
  Timer? timer;
  Timer? groupsUpdateTimer;

  /// Auto-save debounce timer for config changes
  Timer? _configSaveTimer;
  late Config _config;

  /// Config getter/setter with automatic debounced disk persistence.
  /// Every time config is updated (via providers or directly),
  /// it schedules a save to SharedPreferences after 800ms debounce.
  Config get config => _config;
  set config(Config value) {
    _config = value;
    _scheduleConfigSave();
  }

  /// Schedule a debounced save of config to disk.
  /// This ensures config survives app kill from Android recents.
  void _scheduleConfigSave() {
    // Don't save during service (background) mode
    if (isService) return;
    _configSaveTimer?.cancel();
    _configSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        await preferences.saveConfig(_config);
      } catch (e) {
        // Silently log serialization errors to prevent UI dialogs
        debugPrint('[AutoSave] Failed to save config: $e');
      }
    });
  }

  late AppState appState;
  bool isPre = true;
  String? coreSHA256;
  String? coreVersion;
  late PackageInfo packageInfo;
  Function? updateCurrentDelayDebounce;
  late Measure measure;
  late CommonTheme theme;
  late Color accentColor;
  CorePalette? corePalette;
  DateTime? startTime;
  UpdateTasks tasks = [];
  final navigatorKey = GlobalKey<NavigatorState>();
  AppController? _appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  bool isInit = false;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  AppController get appController => _appController!;

  set appController(AppController appController) {
    _appController = appController;
    isInit = true;
  }

  Future<void> initApp(int version) async {
    coreSHA256 = const String.fromEnvironment("CORE_SHA256");
    coreVersion = const String.fromEnvironment("CORE_VERSION");
    isPre = const String.fromEnvironment("APP_ENV") != 'stable';
    appState = AppState(
      version: version,
      viewSize: Size.zero,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
    );
    await _initDynamicColor();
    await init();
  }

  Future<void> _initDynamicColor() async {
    try {
      corePalette = await DynamicColorPlugin.getCorePalette();
      accentColor = await DynamicColorPlugin.getAccentColor() ??
          const Color(defaultPrimaryColor);
    } catch (_) {}
  }

  Future<void> init() async {
    packageInfo = await PackageInfo.fromPlatform();
    config = await preferences.getConfig() ??
        const Config(
          themeProps: defaultThemeProps,
        );
    await globalState.migrateOldData(config);
    await AppLocalizations.load(
      utils.getLocaleForString(config.appSetting.locale) ??
          WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  String get ua => config.patchClashConfig.globalUa ?? packageInfo.ua;

  Future<void> startUpdateTasks([UpdateTasks? tasks]) async {
    if (timer != null && timer!.isActive == true) return;
    if (tasks != null) {
      this.tasks = tasks;
    }
    await executorUpdateTask();
    timer = Timer(const Duration(seconds: 1), () async {
      startUpdateTasks();
    });
  }

  Future<void> executorUpdateTask() async {
    for (final task in tasks) {
      await task();
    }
    timer = null;
  }

  void stopUpdateTasks() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
    timer = null;
  }

  Future<void> handleStart([UpdateTasks? tasks]) async {
    startTime ??= DateTime.now();
    await clashCore.startListener();
    await service?.startVpn();
    startUpdateTasks(tasks);
  }

  Future updateStartTime() async {
    startTime = await clashLib?.getRunTime();
  }

  Future handleStop() async {
    startTime = null;
    await clashCore.stopListener();
    await service?.stopVpn();
    stopUpdateTasks();
  }

  Future<bool?> showMessage({
    String? title,
    required InlineSpan message,
    String? confirmText,
    bool cancelable = true,
  }) async => showCommonDialog<bool>(
      child: Builder(
        builder: (context) => CommonDialog(
            title: title ?? appLocalizations.tip,
            actions: [
              if (cancelable)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: Text(appLocalizations.cancel),
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(confirmText ?? appLocalizations.confirm),
              )
            ],
            child: Container(
              width: 300,
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message],
                  ),
                  style: const TextStyle(
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
          ),
      ),
    );

  // Future<Map<String, dynamic>> getProfileMap(String id) async {
  //   final profilePath = await appPath.getProfilePath(id);
  //   final res = await Isolate.run<Result<dynamic>>(() async {
  //     try {
  //       final file = File(profilePath);
  //       if (!await file.exists()) {
  //         return Result.error("");
  //       }
  //       final value = await file.readAsString();
  //       return Result.success(utils.convertYamlNode(loadYaml(value)));
  //     } catch (e) {
  //       return Result.error(e.toString());
  //     }
  //   });
  //   if (res.isSuccess) {
  //     return res.data as Map<String, dynamic>;
  //   } else {
  //     throw res.message;
  //   }
  // }

  Future<T?> showCommonDialog<T>({
    required Widget child,
    bool dismissible = true,
  }) async => showModal<T>(
      context: navigatorKey.currentState!.context,
      configuration: FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
        barrierDismissible: dismissible,
      ),
      builder: (_) => child,
      filter: commonFilter,
    );

  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
    bool silence = true,
  }) async {
    try {
      final res = await futureFunction();
      return res;
    } catch (e) {
      commonPrint.log("$e");
      if (silence) {
        showNotifier(e.toString());
      } else {
        showMessage(
          title: title ?? appLocalizations.tip,
          message: TextSpan(
            text: e.toString(),
          ),
        );
      }
      return null;
    }
  }

  void showNotifier(String text) {
    if (text.isEmpty) {
      return;
    }
    navigatorKey.currentContext?.showNotifier(text);
  }

  Future<void> openUrl(String url) async {
    final res = await showMessage(
      message: TextSpan(text: url),
      title: appLocalizations.externalLink,
      confirmText: appLocalizations.go,
    );
    if (res != true) {
      return;
    }
    launchUrl(Uri.parse(url));
  }

  Future<void> migrateOldData(Config config) async {
    final clashConfig = await preferences.getClashConfig();
    if (clashConfig != null) {
      config = config.copyWith(
        patchClashConfig: clashConfig,
      );
      preferences.clearClashConfig();
      preferences.saveConfig(config);
    }
  }

  CoreState getCoreState() {
    final currentProfile = config.currentProfile;
    return CoreState(
      vpnProps: config.vpnProps,
      onlyStatisticsProxy: config.appSetting.onlyStatisticsProxy,
      currentProfileName: currentProfile?.label ?? currentProfile?.id ?? "",
      bypassDomain: config.networkProps.bypassDomain,
    );
  }

  Future<SetupParams> getSetupParams({
    required ClashConfig pathConfig,
  }) async {
    final clashConfig = await patchRawConfig(
      patchConfig: pathConfig,
    );
    final params = SetupParams(
      config: clashConfig,
      selectedMap: config.currentProfile?.selectedMap ?? {},
      testUrl: config.appSetting.testUrl,
    );
    return params;
  }

  Future<ClashConfig> syncNetworkSettingsFromProvider(ClashConfig patchConfig) async {
    if (config.appSetting.overrideNetworkSettings) {
      return patchConfig; // User wants to override, keep current settings
    }

    final profile = config.currentProfile;
    if (profile == null) {
      return patchConfig;
    }

    try {
      final profileId = profile.id;
      final configMap = await getProfileConfig(profileId);
      final rawConfig = await handleEvaluate(configMap);

      final providerIpv6 = rawConfig['ipv6'] as bool? ?? patchConfig.ipv6;
      final providerAllowLan = rawConfig['allow-lan'] as bool? ?? patchConfig.allowLan;
      final providerMixedPort = rawConfig['mixed-port'] as int? ?? patchConfig.mixedPort;
      final providerFindProcessModeStr = rawConfig['find-process-mode'] as String?;
      final providerFindProcessMode = providerFindProcessModeStr != null 
          ? FindProcessMode.values.firstWhere(
              (e) => e.name.toLowerCase() == providerFindProcessModeStr.toLowerCase(),
              orElse: () => patchConfig.findProcessMode,
            )
          : patchConfig.findProcessMode;
      
      final providerTunStackStr = rawConfig['tun']?['stack'] as String?;
      final providerTunStack = providerTunStackStr != null
          ? TunStack.values.firstWhere(
              (e) => e.name.toLowerCase() == providerTunStackStr.toLowerCase(),
              orElse: () => patchConfig.tun.stack,
            )
          : patchConfig.tun.stack;

      return patchConfig.copyWith(
        ipv6: providerIpv6,
        allowLan: providerAllowLan,
        mixedPort: providerMixedPort,
        findProcessMode: providerFindProcessMode,
      ).copyWith.tun(stack: providerTunStack);
    } catch (e) {
      commonPrint.log("Error syncing network settings from provider: $e");
      return patchConfig;
    }
  }

  Future<Map<String, dynamic>> patchRawConfig({
    required ClashConfig patchConfig,
  }) async {
    final profile = config.currentProfile;
    if (profile == null) {
      return {};
    }
    final profileId = profile.id;
    final configMap = await getProfileConfig(profileId);
    final rawConfig = await handleEvaluate(configMap);
    
    final realPatchConfig = patchConfig.copyWith(
      tun: patchConfig.tun.getRealTun(config.networkProps.routeMode),
    );
    rawConfig["external-controller"] = realPatchConfig.externalController.value;
    if (rawConfig["external-ui"] == null || rawConfig["external-ui"] == "") {
      rawConfig["external-ui"] = "";
    }
    rawConfig["interface-name"] = "";
    if (rawConfig["external-ui-url"] == null || rawConfig["external-ui-url"] == "") {
      rawConfig["external-ui-url"] = "";
    }
    rawConfig["tcp-concurrent"] = realPatchConfig.tcpConcurrent;
    rawConfig["unified-delay"] = realPatchConfig.unifiedDelay;
    rawConfig["log-level"] = realPatchConfig.logLevel.name;
    rawConfig["port"] = 0;
    rawConfig["socks-port"] = 0;
    rawConfig["keep-alive-interval"] = realPatchConfig.keepAliveInterval;
    rawConfig["port"] = realPatchConfig.port;
    rawConfig["socks-port"] = realPatchConfig.socksPort;
    rawConfig["redir-port"] = realPatchConfig.redirPort;
    rawConfig["tproxy-port"] = realPatchConfig.tproxyPort;
    rawConfig["mode"] = realPatchConfig.mode.name;
    
    // Set network settings: use patchConfig if overriding, otherwise keep provider values
    if (config.appSetting.overrideNetworkSettings) {
      // User wants to override - use values from UI (always write)
      rawConfig["find-process-mode"] = realPatchConfig.findProcessMode.name;
      rawConfig["allow-lan"] = realPatchConfig.allowLan;
      rawConfig["ipv6"] = realPatchConfig.ipv6;
      rawConfig["mixed-port"] = realPatchConfig.mixedPort;
    } else {
      // Use provider values - only set if not already in rawConfig, use patchConfig values (which are synced from provider)
      if (rawConfig["find-process-mode"] == null) {
        rawConfig["find-process-mode"] = realPatchConfig.findProcessMode.name;
      }
      if (rawConfig["allow-lan"] == null) {
        rawConfig["allow-lan"] = realPatchConfig.allowLan;
      }
      if (rawConfig["ipv6"] == null) {
        rawConfig["ipv6"] = realPatchConfig.ipv6;
      }
      if (rawConfig["mixed-port"] == null) {
        rawConfig["mixed-port"] = realPatchConfig.mixedPort;
      }
    }
    
    if (rawConfig["tun"] == null) {
      rawConfig["tun"] = {};
    }
    rawConfig["tun"]["enable"] = realPatchConfig.tun.enable;
    rawConfig["tun"]["device"] = realPatchConfig.tun.device;
    rawConfig["tun"]["dns-hijack"] = realPatchConfig.tun.dnsHijack;
    
    // Set TUN stack
    if (config.appSetting.overrideNetworkSettings) {
      // User wants to override - use value from UI (always write)
      rawConfig["tun"]["stack"] = realPatchConfig.tun.stack.name;
    } else {
      // Use provider value - only set if not already in rawConfig, use patchConfig value (which is synced from provider)
      final currentStack = rawConfig["tun"]["stack"];
      if (currentStack == null) {
        rawConfig["tun"]["stack"] = realPatchConfig.tun.stack.name;
      }
    }
    
    rawConfig["tun"]["route-address"] = realPatchConfig.tun.routeAddress;
    rawConfig["tun"]["auto-route"] = realPatchConfig.tun.autoRoute;
    rawConfig["geodata-loader"] = realPatchConfig.geodataLoader.name;

    // Ensure sniffer is enabled — needed for bypass domains to work in TUN mode.
    // When domains are in fake-ip-filter, mihomo returns real IPs but can't
    // determine the domain from the IP alone. Sniffer extracts the domain from
    // TLS SNI / HTTP Host so DOMAIN rules still match.
    if (rawConfig["sniffer"] == null) {
      rawConfig["sniffer"] = {};
    }
    rawConfig["sniffer"]["enable"] = true;
    rawConfig["sniffer"]["force-dns-mapping"] = true;
    rawConfig["sniffer"]["parse-pure-ip"] = true;
    rawConfig["sniffer"]["override-destination"] = true;
    rawConfig["sniffer"]["sniff"] ??= {
      "HTTP": {"ports": ["80", "8080-8880"]},
      "TLS": {"ports": ["443", "8443"]},
      "QUIC": {"ports": ["443", "8443"]},
    };

    if (rawConfig["sniffer"]?["sniff"] != null) {
      for (final value in (rawConfig["sniffer"]?["sniff"] as Map).values) {
        if (value["ports"] != null && value["ports"] is List) {
          value["ports"] =
              value["ports"]?.map((item) => item.toString()).toList() ?? [];
        }
      }
    }
    if (rawConfig["profile"] == null) {
      rawConfig["profile"] = {};
    }
    if (rawConfig["proxy-providers"] != null) {
      final proxyProviders = rawConfig["proxy-providers"] as Map;
      for (final key in proxyProviders.keys) {
        final proxyProvider = proxyProviders[key];
        if (proxyProvider["type"] != "http") {
          continue;
        }
        if (proxyProvider["url"] != null) {
          proxyProvider["path"] = await appPath.getProvidersFilePath(
            profile.id,
            "proxies",
            proxyProvider["url"],
          );
        }
      }
    }

    if (rawConfig["rule-providers"] != null) {
      final ruleProviders = rawConfig["rule-providers"] as Map;
      for (final key in ruleProviders.keys) {
        final ruleProvider = ruleProviders[key];
        if (ruleProvider["type"] != "http") {
          continue;
        }
        if (ruleProvider["url"] != null) {
          ruleProvider["path"] = await appPath.getProvidersFilePath(
            profile.id,
            "rules",
            ruleProvider["url"],
          );
        }
      }
    }

    rawConfig["profile"]["store-selected"] = false;
    
    final mergedGeoXUrl = <String, dynamic>{};
    final patchGeoX = realPatchConfig.geoXUrl.toJson();
    final profileGeoX = rawConfig["geox-url"];
    
    mergedGeoXUrl['geoip'] = patchGeoX['geoip'];
    mergedGeoXUrl['mmdb'] = patchGeoX['mmdb'];
    mergedGeoXUrl['asn'] = patchGeoX['asn'];
    mergedGeoXUrl['geosite'] = patchGeoX['geosite'];
    
    if (profileGeoX != null && profileGeoX is Map) {
      if (profileGeoX['geoip'] != null) mergedGeoXUrl['geoip'] = profileGeoX['geoip'];
      if (profileGeoX['mmdb'] != null) mergedGeoXUrl['mmdb'] = profileGeoX['mmdb'];
      if (profileGeoX['asn'] != null) mergedGeoXUrl['asn'] = profileGeoX['asn'];
      if (profileGeoX['geosite'] != null) mergedGeoXUrl['geosite'] = profileGeoX['geosite'];
    }
    
    rawConfig["geox-url"] = mergedGeoXUrl;
    rawConfig["global-ua"] = realPatchConfig.globalUa;
    if (rawConfig["hosts"] == null) {
      rawConfig["hosts"] = {};
    }
    for (final host in realPatchConfig.hosts.entries) {
      rawConfig["hosts"][host.key] = host.value.splitByMultipleSeparators;
    }
    if (rawConfig["dns"] == null) {
      rawConfig["dns"] = {};
    }
    final isEnableDns = rawConfig["dns"]["enable"] == true;
    final overrideDns = globalState.config.overrideDns;
    if (overrideDns || !isEnableDns) {
      final dns = switch (!isEnableDns) {
        true => realPatchConfig.dns.copyWith(
            nameserver: [...realPatchConfig.dns.nameserver, "system://"]),
        false => realPatchConfig.dns,
      };
      rawConfig["dns"] = dns.toJson();
      rawConfig["dns"]["nameserver-policy"] = {};
      for (final entry in dns.nameserverPolicy.entries) {
        rawConfig["dns"]["nameserver-policy"][entry.key] =
            entry.value.splitByMultipleSeparators;
      }
    }

    // Add bypass domains to fake-ip-filter so they get real DNS resolution
    // (without this, fake-ip returns fake IPs → DIRECT traffic goes to wrong
    // server → SSL certificate mismatch / ERR_CERT_COMMON_NAME_INVALID)
    if (rawConfig["dns"] != null) {
      final currentFilter =
          List<String>.from(rawConfig["dns"]["fake-ip-filter"] ?? []);
      for (final d in config.networkProps.bypassDomain) {
        if (d == 'localhost' ||
            d == '*.local' ||
            d.startsWith('127.') ||
            d.startsWith('10.') ||
            d.startsWith('172.') ||
            d.startsWith('192.168.') ||
            RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(d)) {
          continue;
        }
        String filterEntry;
        if (d.startsWith('+.') || d.startsWith('*.')) {
          filterEntry = '+.${d.substring(2)}';
        } else if (d.startsWith('*')) {
          filterEntry = '+.${d.substring(1)}';
        } else {
          filterEntry = '+.$d';
        }
        if (!currentFilter.contains(filterEntry)) {
          currentFilter.add(filterEntry);
        }
      }
      rawConfig["dns"]["fake-ip-filter"] = currentFilter;
    }

    var rules = [];
    if (rawConfig["rules"] != null) {
      rules = rawConfig["rules"];
    }
    rawConfig.remove("rules");

    final overrideData = profile.overrideData;
    if (overrideData.enable && config.scriptProps.currentScript == null) {
      if (overrideData.rule.type == OverrideRuleType.override) {
        rules = overrideData.runningRule;
      } else {
        rules = [...overrideData.runningRule, ...rules];
      }
    }
    // Inject bypass domain rules as DIRECT before other rules
    final bypassDomains = config.networkProps.bypassDomain;
    final bypassRules = <String>[];
    for (final d in bypassDomains) {
      // Skip IP/local patterns — they're not domain rules
      if (d == 'localhost' ||
          d.startsWith('127.') ||
          d.startsWith('10.') ||
          d.startsWith('172.') ||
          d.startsWith('192.168.') ||
          d == '*.local' ||
          RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(d)) {
        continue;
      }
      if (d.startsWith('*.') || d.startsWith('+.')) {
        // *.example.com → DOMAIN-SUFFIX,example.com,DIRECT
        bypassRules.add('DOMAIN-SUFFIX,${d.substring(2)},DIRECT');
      } else if (d.startsWith('*')) {
        // *example.com → DOMAIN-SUFFIX,example.com,DIRECT
        bypassRules.add('DOMAIN-SUFFIX,${d.substring(1)},DIRECT');
      } else {
        // example.com → DOMAIN-SUFFIX,example.com,DIRECT (suffix for subdomains too)
        bypassRules.add('DOMAIN-SUFFIX,${d},DIRECT');
      }
    }
    rawConfig["rule"] = [...bypassRules, ...rules];
    return rawConfig;
  }

  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    final configMap = await switch (clashLibHandler != null) {
      true => clashLibHandler!.getConfig(profileId),
      false => clashCore.getConfig(profileId),
    };
    configMap["rules"] = configMap["rule"];
    configMap.remove("rule");
    return configMap;
  }

  Future<Map<String, dynamic>> handleEvaluate(
    Map<String, dynamic> config,
  ) async {
    final currentScript = globalState.config.scriptProps.currentScript;
    if (currentScript == null) {
      return config;
    }
    if (config["proxy-providers"] == null) {
      config["proxy-providers"] = {};
    }
    final configJs = json.encode(config);
    final runtime = getJavascriptRuntime();
    final res = await runtime.evaluateAsync("""
      ${currentScript.content}
      main($configJs)
    """);
    if (res.isError) {
      throw res.stringResult;
    }
    final value = switch (res.rawResult is Pointer) {
      true => runtime.convertValue<Map<String, dynamic>>(res),
      false => Map<String, dynamic>.from(res.rawResult),
    };
    return value ?? config;
  }
}

final globalState = GlobalState();

class DetectionState {

  factory DetectionState() {
    _instance ??= DetectionState._internal();
    return _instance!;
  }

  DetectionState._internal();
  static DetectionState? _instance;
  bool? _preIsStart;
  Timer? _setTimeoutTimer;
  CancelToken? cancelToken;
  DateTime? _lastManualCheck;

  final state = ValueNotifier<NetworkDetectionState>(
    const NetworkDetectionState(
      isTesting: false,
      isLoading: true,
      ipInfo: null,
    ),
  );

  void startCheck() {
    debouncer.call(
      FunctionTag.checkIp,
      _checkIp,
      duration: const Duration(
        milliseconds: 1200,
      ),
    );
  }

  bool forceCheck() {
    if (_lastManualCheck != null) {
      final timeSinceLastCheck = DateTime.now().difference(_lastManualCheck!);
      if (timeSinceLastCheck.inSeconds < 15) {
        return false;
      }
    }
    _lastManualCheck = DateTime.now();
    _checkIp();
    return true;
  }

  Future<void> _checkIp() async {
    final appState = globalState.appState;
    final isInit = appState.isInit;
    if (!isInit) return;
    final isStart = appState.runTime != null;
    if (_preIsStart == false &&
        _preIsStart == isStart &&
        state.value.ipInfo != null) {
      return;
    }
    _clearSetTimeoutTimer();
    state.value = state.value.copyWith(
      isLoading: true,
      ipInfo: null,
    );
    _preIsStart = isStart;
    if (cancelToken != null) {
      cancelToken!.cancel();
      cancelToken = null;
    }
    cancelToken = CancelToken();
    state.value = state.value.copyWith(
      isTesting: true,
    );
    final res = await request.checkIp(cancelToken: cancelToken);
    if (res.isError) {
      state.value = state.value.copyWith(
        isLoading: true,
        ipInfo: null,
      );
      return;
    }
    final ipInfo = res.data;
    state.value = state.value.copyWith(
      isTesting: false,
    );
    if (ipInfo != null) {
      state.value = state.value.copyWith(
        isLoading: false,
        ipInfo: ipInfo,
      );
      return;
    }
    _clearSetTimeoutTimer();
    _setTimeoutTimer = Timer(const Duration(milliseconds: 300), () {
      state.value = state.value.copyWith(
        isLoading: false,
        ipInfo: null,
      );
    });
  }

  void _clearSetTimeoutTimer() {
    if (_setTimeoutTimer != null) {
      _setTimeoutTimer?.cancel();
      _setTimeoutTimer = null;
    }
  }
}

final detectionState = DetectionState();
