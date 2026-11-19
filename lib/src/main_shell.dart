part of '../main.dart';

class MainShell extends StatefulWidget {
  final Function(AppThemeModeSetting) onThemeChanged;
  final AppThemeModeSetting currentTheme;

  const MainShell({
    super.key,
    required this.onThemeChanged,
    required this.currentTheme,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final V2ray flutterV2ray;
  final ValueNotifier<V2RayStatus> _statusNotifier =
      ValueNotifier<V2RayStatus>(V2RayStatus());
  String _connState = 'DISCONNECTED';
  String coreVersion = '...';

  List<ServerItem> servers = [];
  List<SubscriptionItem> subscriptions = [];
  String selectedServerId = '';
  String selectedGroupFilter = 'ALL';
  String selectedCountryFilter = 'ALL';
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  PingMode selectedPingMode = PingMode.real;
  int pingProxyTimeoutSec = 5;
  bool pingBestOfTwo = false;
  bool pingBypassRouting = false;
  String pingTestUrl = kDefaultPingUrl;
  bool isTestingAll = false;
  int pingTestsCompleted = 0;
  int pingTestsTotal = 0;

  bool _subUpdateMutex = false;
  bool isCheckingUpdate = false;
  bool isFindingFastest = false;

  bool isProxyOnly = false;
  final Set<String> _sortedGroups = <String>{};
  final Set<String> _testingGroups = <String>{};
  final Set<String> _countryGroups = <String>{};
  final Set<String> bypassApps = <String>{};
  List<String> customDirectIps = <String>[];
  List<String> customDirectDomains = <String>[];
  String customRoutingName = '';
  List<StringMap> _installedApps = [];
  bool _appsLoading = false;
  bool iranianAutoDone = false;
  String _appsQuery = '';
  bool enableIPv6 = false;
  int mtuSize = 1500;
  bool keepCpuAlive = true;
  final Set<String> _collapsedGroups = <String>{};
  bool bypassLan = true;
  bool bypassIran = true;
  bool enableMux = false;
  bool allowInsecureDefault = false;
  bool autoUpdateSubs = true;
  bool enableTlsFragment = false;
  String fragmentPackets = 'tlshello';
  String fragmentLength = '10-20';
  String fragmentInterval = '10-20';
  bool enableAdBlock = false;
  bool connectionHealthMonitor = false;
  bool autoConnectOnBoot = false;

  Timer? _failoverTimer;
  int _failoverStrikes = 0;
  bool _isFailoverSwitching = false;

  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;

  // آپشن ۱: حالت مینیمال (Hide everything)
  bool _hideEverything = false;

  // آپشن ۲: صندوق پیام‌ها و اعلان‌ها
  final List> _inboxMessages = [];
  bool _hasUnreadMessages = false;

  // آپشن ۳: تست IP و لوکیشن واقعی
  String _currentIp = '';
  String _currentIpCountry = '';
  bool _isCheckingIp = false;

  // آپشن ۴: سرورهای برگزیده (Favorites)
  final Set<String> _favoriteServerIds = <String>{};

  // آپشن ۶: تاریخچه سرعت برای نمودار زنده
  final List<double> _dlHistory = List<double>.filled(24, 0, growable: true);
  final List<double> _ulHistory = List<double>.filled(24, 0, growable: true);

  String selectedDns = '1.1.1.1';
  String hwid = '';
  String updateRepoUrl =
      'https://api.github.com/repos/$kUpdateRepo/releases/latest';
  String availableVersion = '';
  String availableApkUrl = '';
  String availableChangelog = '';
  double? downloadProgress;

  bool get isConnected => _connState == 'CONNECTED';
  bool get isConnecting => _connState == 'CONNECTING';
  bool get hasSleepTimer => _sleepTimer != null && _sleepRemaining.inSeconds > 0;

  @override
  void dispose() {
    _failoverTimer?.cancel();
    _sleepTimer?.cancel();
    _searchController.dispose();
    _statusNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    kQuickControlsChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'quickToggleVpn') {
        await toggleVpn();
      } else if (call.method == 'safeDisconnectVpn') {
        if (isConnected || isConnecting) {
          await _stopVpn();
        }
      }
    });
    flutterV2ray = V2ray(
      onStatusChanged: (status) {
        _statusNotifier.value = status;
        _dlHistory.removeAt(0);
        _dlHistory.add(status.downloadSpeed.toDouble());
        _ulHistory.removeAt(0);
        _ulHistory.add(status.uploadSpeed.toDouble());

        if (status.state == 'CONNECTED' && _currentIp.isEmpty && !_isCheckingIp) {
          unawaited(_checkRealIp());
        } else if (status.state == 'DISCONNECTED') {
          _currentIp = '';
          _currentIpCountry = '';
        }

        if (status.state != _connState) {
          if (mounted) {
            setState(() {
              _connState = status.state;
              if (_pendingTarget == true && status.state == 'CONNECTED') {
                _pendingTarget = null;
              }
            });
          }
          if (status.state == 'CONNECTED') {
            _startFailoverWatchdog();
          } else if (status.state == 'DISCONNECTED') {
            _stopFailoverWatchdog();
            _cancelSleepTimer(silent: true);
          }
          unawaited(
            _syncNativeConnectionState(status.state == 'CONNECTED', status.state),
          );
        }
      },
    );
    initEngineAndLoadData();
  }

  Future<void> initEngineAndLoadData() async {
    try {
      await flutterV2ray.initialize(
        notificationIconResourceType: 'drawable',
        notificationIconResourceName: 'ic_notification_vpn',
      );
    } catch (e) {
      if (mounted) showSnack('راه‌اندازی هسته Xray ناموفق بود: $e');
    }
    await loadPersistentData();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => coreVersion = 'هستهٔ Xray v26.10.31');
    await _syncNativeConnectionState(isConnected, _connState);
    await _consumePendingQuickAction();
    await _maybeShowOnboarding();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _autoUpdateOldSubscriptions();
      unawaited(checkForAppUpdate(silent: true));
      unawaited(_setupBackgroundUpdates());
    });
  }

  Future<void> _setupBackgroundUpdates() async {
    try {
      await UpdateNotifier.init();
      await UpdateNotifier.requestPermission();
      await Workmanager().initialize(shinUpdateDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        'shin-update-check',
        'shinUpdateCheck',
        frequency: const Duration(hours: 12),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  Future<void> _maybeShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_done') ?? false) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const OnboardingScreen(),
      fullscreenDialog: true,
    ));
  }

  Future<void> _syncNativeConnectionState(bool connected, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bg_vpn_connected', connected);
      await kQuickControlsChannel.invokeMethod('setConnectionState', {
        'connected': connected,
        'status': status,
      });
    } catch (_) {}
  }

  Future<void> _consumePendingQuickAction() async {
    try {
      final action =
          await kQuickControlsChannel.invokeMethod('consumePendingAction');
      if (!mounted) return;
      if (action == 'toggleVpn') {
        await toggleVpn();
      } else if (action == 'safeDisconnect' && (isConnected || isConnecting)) {
        await _stopVpn();
      }
    } catch (_) {}
  }

  Future<void> savePersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedServerId', selectedServerId);
      await prefs.setBool('isProxyOnly', isProxyOnly);
      await prefs.setBool('bypassLan', bypassLan);
      await prefs.setBool('bypassIran', bypassIran);
      await prefs.setBool('enableMux', enableMux);
      await prefs.setBool('allowInsecureDefault', allowInsecureDefault);
      await prefs.setBool('autoUpdateSubs', autoUpdateSubs);
      await prefs.setBool('enableTlsFragment', enableTlsFragment);
      await prefs.setString('fragmentPackets', fragmentPackets);
      await prefs.setString('fragmentLength', fragmentLength);
      await prefs.setString('fragmentInterval', fragmentInterval);
      await prefs.setBool('enableAdBlock', enableAdBlock);
      await prefs.setBool('connectionHealthMonitor', connectionHealthMonitor);
      await prefs.setBool('auto_connect_on_boot', autoConnectOnBoot);
      await prefs.setString('selectedDns', selectedDns);
      await prefs.setString('pingMode', selectedPingMode.name);
      await prefs.setString('hwid', hwid);
      await prefs.setString('updateRepoUrl', updateRepoUrl);
      await prefs.setInt('pingProxyTimeoutSec', pingProxyTimeoutSec);
      await prefs.setBool('pingBestOfTwo', pingBestOfTwo);
      await prefs.setBool('pingBypassRouting', pingBypassRouting);
      await prefs.setBool('enableIPv6', enableIPv6);
      await prefs.setInt('mtuSize', mtuSize);
      await prefs.setBool('keepCpuAlive', keepCpuAlive);
      await prefs.setStringList('bypassApps', bypassApps.toList());
      await prefs.setStringList('customDirectIps', customDirectIps);
      await prefs.setStringList('customDirectDomains', customDirectDomains);
      await prefs.setString('customRoutingName', customRoutingName);
      await prefs.setBool('iranianAutoDone', iranianAutoDone);
      await prefs.setString('pingTestUrl', pingTestUrl);
      await prefs.setStringList('countryGroups', _countryGroups.toList());
      await prefs.setStringList('favoriteServerIds', _favoriteServerIds.toList());

      final active = selectedServer;
      if (active != null) {
        await prefs.setString(
          'native_ready_config',
          buildCustomizedConfig(active.fullJsonConfig),
        );
        await prefs.setString('native_ready_remark', active.remark);
      } else {
        await prefs.remove('native_ready_config');
        await prefs.remove('native_ready_remark');
      }

      final serversJson = servers.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList('saved_servers_list', serversJson);

      final subsJson =
          subscriptions.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList('saved_subs_list', subsJson);
    } catch (_) {}
  }

  Future<void> loadPersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      var savedHwid = prefs.getString('hwid') ?? '';
      if (savedHwid.isEmpty) {
        final rnd = Random.secure();
        savedHwid = List.generate(
          16,
          (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }

      final loadedServers = <ServerItem>[];
      for (final e
          in prefs.getStringList('saved_servers_list') ?? <String>[]) {
        try {
          loadedServers.add(ServerItem.fromJson(JsonMap.from(jsonDecode(e))));
        } catch (_) {}
      }
      final loadedSubs = <SubscriptionItem>[];
      for (final e in prefs.getStringList('saved_subs_list') ?? <String>[]) {
        try {
          loadedSubs
              .add(SubscriptionItem.fromJson(JsonMap.from(jsonDecode(e))));
        } catch (_) {}
      }

      var nextCustomDirectIps = List<String>.from(
          prefs.getStringList('customDirectIps') ?? const <String>[]);
      var nextCustomDirectDomains = List<String>.from(
          prefs.getStringList('customDirectDomains') ?? const <String>[]);
      var nextCustomRoutingName = prefs.getString('customRoutingName') ?? '';

      final routingV2Migrated =
          prefs.getBool('routing_parser_v2_migrated') ?? false;
      if (!routingV2Migrated) {
        final parsed = parseRoutingInput(kBuiltinIranRoutingLink);
        if (parsed != null) {
          nextCustomDirectIps = {
            ...nextCustomDirectIps,
            ...parsed.directIps,
          }.toList();
          nextCustomDirectDomains = {
            ...nextCustomDirectDomains,
            ...parsed.directDomains,
          }.toList();
          if (nextCustomRoutingName.isEmpty) {
            nextCustomRoutingName = parsed.name;
          }
        }
        await prefs.setBool('routing_parser_v2_migrated', true);
      }

      if (!mounted) return;
      setState(() {
        hwid = savedHwid;
        selectedServerId = prefs.getString('selectedServerId') ?? '';
        isProxyOnly = false;
        bypassLan = prefs.getBool('bypassLan') ?? true;
        bypassIran = prefs.getBool('bypassIran') ?? true;
        enableMux = prefs.getBool('enableMux') ?? false;
        allowInsecureDefault = prefs.getBool('allowInsecureDefault') ?? false;
        autoUpdateSubs = prefs.getBool('autoUpdateSubs') ?? true;
        enableTlsFragment = prefs.getBool('enableTlsFragment') ?? false;
        fragmentPackets = prefs.getString('fragmentPackets') ?? 'tlshello';
        fragmentLength = prefs.getString('fragmentLength') ?? '10-20';
        fragmentInterval = prefs.getString('fragmentInterval') ?? '10-20';
        enableAdBlock = prefs.getBool('enableAdBlock') ?? false;
        connectionHealthMonitor = prefs.getBool('connectionHealthMonitor') ??
            prefs.getBool('autoFailover') ??
            false;
        autoConnectOnBoot = prefs.getBool('auto_connect_on_boot') ?? false;
        selectedDns = prefs.getString('selectedDns') ?? '1.1.1.1';
        updateRepoUrl =
            'https://api.github.com/repos/$kUpdateRepo/releases/latest';
        selectedPingMode = PingMode.values.firstWhere(
          (mode) => mode.name == prefs.getString('pingMode'),
          orElse: () => PingMode.real,
        );
        pingProxyTimeoutSec = prefs.getInt('pingProxyTimeoutSec') ?? 5;
        pingBestOfTwo = prefs.getBool('pingBestOfTwo') ?? false;
        pingBypassRouting = prefs.getBool('pingBypassRouting') ?? false;
        enableIPv6 = prefs.getBool('enableIPv6') ?? false;
        mtuSize = prefs.getInt('mtuSize') ?? 1500;
        keepCpuAlive = prefs.getBool('keepCpuAlive') ?? true;
        bypassApps
          ..clear()
          ..addAll(prefs.getStringList('bypassApps') ?? const <String>[]);
        customDirectIps = nextCustomDirectIps;
        customDirectDomains = nextCustomDirectDomains;
        customRoutingName = nextCustomRoutingName;
        iranianAutoDone = prefs.getBool('iranianAutoDone') ?? false;
        pingTestUrl = prefs.getString('pingTestUrl') ?? kDefaultPingUrl;
        _countryGroups
          ..clear()
          ..addAll(prefs.getStringList('countryGroups') ?? const <String>[]);
        _favoriteServerIds
          ..clear()
          ..addAll(prefs.getStringList('favoriteServerIds') ?? const <String>[]);
        servers = loadedServers;
        subscriptions = loadedSubs;
        if (selectedServerId.isEmpty && servers.isNotEmpty) {
          selectedServerId = servers.first.id;
        }
      });
      final builtinApplied = prefs.getBool('builtin_routing_applied') ?? false;
      if (!builtinApplied) {
        await prefs.setBool('builtin_routing_applied', true);
        await savePersistentData();
      }
    } catch (_) {}
  }

  static String flagOf(String code) {
    if (code.length != 2) return '🌐';
    final c = code.toUpperCase();
    return String.fromCharCodes([
      0x1F1E6 + c.codeUnitAt(0) - 0x41,
      0x1F1E6 + c.codeUnitAt(1) - 0x41,
    ]);
  }

  Future<JsonMap?> _fetchJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // --- آپشن ۲: صندوق پیام‌ها ---
  void _addInboxMessage(String title, String body) {
    if (!mounted) return;
    setState(() {
      _inboxMessages.insert(0, {
        'title': title,
        'body': body,
        'time':
            '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      });
      _hasUnreadMessages = true;
    });
  }

  void _showInboxSheet() {
    setState(() => _hasUnreadMessages = false);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(
                Icons.mail_outline_rounded,
                const Color(0xFF6366F1),
                'صندوق پیام‌ها و اعلان‌ها',
                'وضعیت آپدیت‌ها، اشتراک و هشدارها',
              ),
              const SizedBox(height: 14),
              if (availableVersion.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.system_update_rounded,
                      color: Color(0xFF3B82F6)),
                  title: Text('نسخه جدید $availableVersion آماده نصب است'),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showUpdateSheet();
                    },
                    child: const Text('نصب'),
                  ),
                ),
              if (_inboxMessages.isEmpty && availableVersion.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'هیچ پیام جدیدی وجود ندارد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _inboxMessages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = _inboxMessages[i];
                      return ListTile(
                        title: Text(m['title'] ?? '',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(m['body'] ?? '',
                            style: const TextStyle(fontSize: 12)),
                        trailing: Text(m['time'] ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- آپشن ۳: تست IP و لوکیشن واقعی ---
  Future<void> _checkRealIp() async {
    if (_isCheckingIp) return;
    if (mounted) setState(() => _isCheckingIp = true);
    try {
      final info = await _fetchJson('https://api.country.is/');
      if (info != null && mounted) {
        setState(() {
          _currentIp = (info['ip'] ?? '').toString();
          _currentIpCountry = (info['country'] ?? '').toString();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isCheckingIp = false);
    }
  }

  // --- آپشن ۴: سرورهای برگزیده ---
  void _toggleFavorite(ServerItem server) {
    setState(() {
      if (_favoriteServerIds.contains(server.id)) {
        _favoriteServerIds.remove(server.id);
      } else {
        _favoriteServerIds.add(server.id);
      }
    });
    savePersistentData();
  }

  // --- آپشن ۵: پروفایل آماده اپراتورها ---
  void _showCarrierPresetSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(
                Icons.cell_tower_rounded,
                const Color(0xFF10B981),
                'پروفایل آماده اپراتورها',
                'تنظیم خودکار Fragment، MTU و DNS با یک لمس',
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.sim_card_rounded,
                    color: Color(0xFF0EA5E9)),
                title: const Text('همراه اول (MCI)'),
                subtitle: const Text(
                    'Fragment: tlshello (10-20) • MTU: 1400 • DNS: 1.1.1.1'),
                onTap: () async {
                  Navigator.pop(ctx);
                  _applySetting(() {
                    enableTlsFragment = true;
                    fragmentPackets = 'tlshello';
                    fragmentLength = '10-20';
                    fragmentInterval = '10-20';
                    mtuSize = 1400;
                    selectedDns = '1.1.1.1';
                  });
                  await savePersistentData();
                  await reconnectIfNeeded();
                  _addInboxMessage('پروفایل اپراتور', 'تنظیمات همراه اول اعمال شد.');
                  showSnack('پروفایل همراه اول اعمال شد ✅');
                },
              ),
              ListTile(
                leading: const Icon(Icons.sim_card_rounded,
                    color: Color(0xFFF59E0B)),
                title: const Text('ایرانسل (Irancell)'),
                subtitle: const Text(
                    'Fragment: قوی (1-3) • MTU: 1280 • DNS: 8.8.8.8'),
                onTap: () async {
                  Navigator.pop(ctx);
                  _applySetting(() {
                    enableTlsFragment = true;
                    fragmentPackets = '1-3';
                    fragmentLength = '5-10';
                    fragmentInterval = '5-10';
                    mtuSize = 1280;
                    selectedDns = '8.8.8.8';
                  });
                  await savePersistentData();
                  await reconnectIfNeeded();
                  _addInboxMessage('پروفایل اپراتور', 'تنظیمات ایرانسل اعمال شد.');
                  showSnack('پروفایل ایرانسل اعمال شد ✅');
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.wifi_rounded, color: Color(0xFF10B981)),
                title: const Text('وای‌فای / مخابرات (Wi-Fi)'),
                subtitle: const Text(
                    'Fragment: خاموش • MTU: 1500 • DNS: 1.1.1.1'),
                onTap: () async {
                  Navigator.pop(ctx);
                  _applySetting(() {
                    enableTlsFragment = false;
                    mtuSize = 1500;
                    selectedDns = '1.1.1.1';
                  });
                  await savePersistentData();
                  await reconnectIfNeeded();
                  _addInboxMessage('پروفایل اپراتور', 'تنظیمات وای‌فای اعمال شد.');
                  showSnack('پروفایل وای‌فای اعمال شد ✅');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  else {
        showSnack('انتخاب سرور: ${best.remark}');
      }

      if (isConnected || isConnecting) {
        await reconnectIfNeeded();
      } else {
        await toggleVpn();
      }
    } finally {
      if (mounted) setState(() => isFindingFastest = false);
    }
  }

  int _removeFailedServers() {
    final before = servers.length;
    servers.removeWhere((s) {
      final p = s.pingFor(PingMode.real);
      return p != null && p <= 0 && s.id != selectedServerId;
    });
    final removed = before - servers.length;
    if (removed > 0) {
      setState(() {});
      savePersistentData();
    }
    return removed;
  }

  Future<void> _scanQrFromCamera() async {
    try {
      final code =
          await kQuickControlsChannel.invokeMethod<String>('scanQrCode');
      if (code != null && code.trim().isNotEmpty) {
        await processInput(code.trim());
      }
    } on PlatformException catch (e) {
      showSnack('اسکنر QR در دسترس نیست: ${e.message ?? e.code}');
    } catch (_) {
      showSnack('اسکن QR انجام نشد');
    }
  }

  void _showQrShareSheet(String title, String subtitle, String payload) {
    if (payload.trim().isEmpty) {
      showSnack('داده‌ای برای ساخت QR Code وجود ندارد');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(
                Icons.qr_code_2_rounded,
                const Color(0xFF3B82F6),
                title,
                subtitle,
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('کپی متن لینک'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: payload));
                  Navigator.pop(ctx);
                  showSnack('لینک کپی شد');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String buildCustomizedConfig(String rawJson) {
    try {
      final JsonMap config = JsonMap.from(jsonDecode(rawJson));
      final serverEp = extractServerEndpoint(rawJson);
      final isServerDomain =
          serverEp != null && InternetAddress.tryParse(serverEp.host) == null;
      final effectiveDns = enableAdBlock ? '94.140.14.14' : selectedDns;

      config['dns'] = {
        'servers': <dynamic>[
          if (isServerDomain)
            {
              'address': 'localhost',
              'domains': ['full:${serverEp.host}'],
            },
          effectiveDns,
          if (effectiveDns != '1.1.1.1') '1.1.1.1',
          if (effectiveDns != '8.8.8.8') '8.8.8.8',
          if (bypassIran)
            {
              'address': '217.218.127.127',
              'port': 53,
              'domains': ['regexp:.*\\.ir\$'],
            },
        ],
        'queryStrategy': enableIPv6 ? 'UseIP' : 'UseIPv4',
      };

      if (config['inbounds'] is! List || (config['inbounds'] as List).isEmpty) {
        config['inbounds'] = LinkParser.standardInbounds();
      } else {
        final List inbounds = config['inbounds'];
        bool hasHttp = false;
        for (final inb in inbounds) {
          if (inb is Map) {
            if (inb['protocol'] == 'socks') {
              inb['port'] ??= 10808;
              inb['listen'] ??= '127.0.0.1';
              if (inb['settings'] is Map) {
                inb['settings']['udp'] = true;
                inb['settings']['auth'] ??= 'noauth';
              } else {
                inb['settings'] = {
                  'auth': 'noauth',
                  'udp': true,
                  'userLevel': 8
                };
              }
            }
            if (inb['protocol'] == 'http') {
              hasHttp = true;
            }
            inb['sniffing'] = {
              'enabled': true,
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': false,
            };
          }
        }
        if (!hasHttp) {
          inbounds.add({
            'tag': 'http',
            'port': 10809,
            'protocol': 'http',
            'listen': '127.0.0.1',
            'settings': {'userLevel': 8},
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': false,
            },
          });
        }
      }

      String mainProxyTag = 'proxy';
      if (config['outbounds'] is List &&
          (config['outbounds'] as List).isNotEmpty) {
        final List outbounds = config['outbounds'];
        if (outbounds[0] is Map) {
          outbounds[0]['tag'] ??= 'proxy';
          mainProxyTag = outbounds[0]['tag'].toString();
          outbounds[0]['mux'] = {
            'enabled': enableMux,
            'concurrency': enableMux ? 8 : -1,
          };
          if (allowInsecureDefault &&
              outbounds[0]['streamSettings'] is Map &&
              outbounds[0]['streamSettings']['tlsSettings'] is Map) {
            outbounds[0]['streamSettings']['tlsSettings']['allowInsecure'] =
                true;
          }

          if (enableTlsFragment) {
            final proto =
                (outbounds[0]['protocol'] ?? '').toString().toLowerCase();
            if (proto == 'vless' || proto == 'vmess' || proto == 'trojan') {
              outbounds[0]['streamSettings'] ??= <String, dynamic>{};
              if (outbounds[0]['streamSettings'] is Map) {
                final streamMap = outbounds[0]['streamSettings'] as Map;
                streamMap['sockopt'] ??= <String, dynamic>{};
                if (streamMap['sockopt'] is Map) {
                  (streamMap['sockopt'] as Map)['dialerProxy'] = 'fragment';
                }
              }
              outbounds.removeWhere((o) => o is Map && o['tag'] == 'fragment');
              outbounds.add({
                'tag': 'fragment',
                'protocol': 'freedom',
                'settings': {
                  'fragment': {
                    'packets': fragmentPackets,
                    'length': fragmentLength,
                    'interval': fragmentInterval,
                  },
                },
                'streamSettings': {
                  'sockopt': {
                    'tcpNoDelay': true,
                  },
                },
              });
            }
          }
        }
        if (!outbounds.any((o) => o is Map && o['tag'] == 'direct')) {
          outbounds.add({
            'tag': 'direct',
            'protocol': 'freedom',
            'settings': {'domainStrategy': 'UseIP'}
          });
        }
        if (!outbounds.any((o) => o is Map && o['tag'] == 'blackhole')) {
          outbounds.add({
            'tag': 'blackhole',
            'protocol': 'blackhole',
            'settings': {}
          });
        }
        if (!outbounds.any((o) => o is Map && o['tag'] == 'dns-out')) {
          outbounds.add({'tag': 'dns-out', 'protocol': 'dns'});
        }
      }
      final List<dynamic> rules = [
        {
          'type': 'field',
          'inboundTag': ['socks', 'http'],
          'port': '53',
          'outboundTag': 'dns-out',
        },
        {
          'type': 'field',
          'network': 'udp',
          'port': '443',
          'outboundTag': 'blackhole',
        },
      ];

      if (enableAdBlock) {
        rules.add({
          'type': 'field',
          'domain': [
            'domain:doubleclick.net',
            'domain:googlesyndication.com',
            'domain:googleadservices.com',
            'domain:adservice.google.com',
            'domain:analytics.google.com',
            'domain:app-measurement.com',
            'domain:appsflyer.com',
            'domain:adjust.com',
            'domain:applovin.com',
            'domain:unityads.unity3d.com',
            'domain:adcolony.com',
            'domain:vungle.com',
            'domain:inmobi.com',
            'domain:mopub.com',
            'domain:criteo.com',
            'domain:taboola.com',
            'domain:outbrain.com',
            'keyword:adserver',
            'keyword:doubleclick',
          ],
          'outboundTag': 'blackhole',
        });
      }

      if (bypassLan) {
        rules.add({
          'type': 'field',
          'ip': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '127.0.0.0/8'
          ],
          'outboundTag': 'direct'
        });
      }
      if (bypassIran) {
        final directDomains = <String>{
          'regexp:.*\\.ir\$',
          ...customDirectDomains,
        };
        rules.add({
          'type': 'field',
          'domain': directDomains.toList(),
          'outboundTag': 'direct'
        });

        final directIps = <String>{
          '217.218.127.127/32',
          '2.144.0.0/14',
          '5.52.0.0/16',
          '31.2.128.0/17',
          '37.98.0.0/16',
          '78.38.0.0/15',
          '79.127.0.0/16',
          ...customDirectIps,
        };
        rules.add({
          'type': 'field',
          'ip': directIps.toList(),
          'outboundTag': 'direct'
        });
      } else if (customDirectIps.isNotEmpty || customDirectDomains.isNotEmpty) {
        final safeDomains = customDirectDomains.toList();
        if (safeDomains.isNotEmpty) {
          rules.add({
            'type': 'field',
            'domain': safeDomains,
            'outboundTag': 'direct'
          });
        }
        final safeIps = customDirectIps.toList();
        if (safeIps.isNotEmpty) {
          rules.add({
            'type': 'field',
            'ip': safeIps,
            'outboundTag': 'direct'
          });
        }
      }

      rules.add({
        'type': 'field',
        'network': 'tcp,udp',
        'outboundTag': mainProxyTag,
      });

      config['routing'] = {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      };

      return jsonEncode(config);
    } catch (_) {
      return rawJson;
    }
  }

  String buildLightweightPingConfig(String rawJson) {
    try {
      final JsonMap config = JsonMap.from(jsonDecode(rawJson));
      config['log'] = {'loglevel': 'none'};
      config.remove('routing');
      config.remove('dns');
      if (config['inbounds'] is List) {
        for (final inb in config['inbounds']) {
          if (inb is Map) {
            inb.remove('sniffing');
          }
        }
      }
      if (allowInsecureDefault &&
          config['outbounds'] is List &&
          (config['outbounds'] as List).isNotEmpty) {
        final first = config['outbounds'][0];
        if (first is Map &&
            first['streamSettings'] is Map &&
            first['streamSettings']['tlsSettings'] is Map) {
          first['streamSettings']['tlsSettings']['allowInsecure'] = true;
        }
      }
      return jsonEncode(config);
    } catch (_) {
      return rawJson;
    }
  }

  ServerItem? get selectedServer {
    if (servers.isEmpty) return null;
    try {
      return servers.firstWhere((s) => s.id == selectedServerId);
    } catch (_) {
      return servers.first;
    }
  }

  bool _vpnBusy = false;
  bool? _pendingTarget;
  int _pendingToken = 0;

  void _setPending(bool? value) {
    if (mounted) setState(() => _pendingTarget = value);
  }

  Future<void> _waitForState(String target, {int ms = 2500}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end) && _connState != target) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _stopVpn() async {
    final stoppedStatus = V2RayStatus(state: 'DISCONNECTING');
    _statusNotifier.value = stoppedStatus;
    if (mounted) {
      setState(() => _connState = 'DISCONNECTING');
    }
    unawaited(_syncNativeConnectionState(false, 'DISCONNECTING'));
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await flutterV2ray.stopV2Ray();
      } catch (_) {}
      await _waitForState('DISCONNECTED');
      if (_connState == 'DISCONNECTED') break;
    }
    _statusNotifier.value = V2RayStatus(state: 'DISCONNECTED');
    if (mounted && _connState != 'DISCONNECTED') {
      setState(() => _connState = 'DISCONNECTED');
    }
    await _syncNativeConnectionState(false, 'DISCONNECTED');
    _setPending(null);
  }

  Future<void> toggleVpn() async {
    if (_vpnBusy || _pendingTarget != null) return;
    _vpnBusy = true;
    HapticFeedback.mediumImpact();
    final wantConnect = !(isConnected || isConnecting);
    var started = false;
    try {
      if (!wantConnect) {
        _setPending(false);
        await _stopVpn();
        return;
      }

      final target = selectedServer;
      if (target == null) {
        showSnack('لطفاً ابتدا یک سرور اضافه کنید');
        return;
      }

      if (!isProxyOnly && !await flutterV2ray.requestPermission()) {
        showSnack('مجوز ساخت تونل VPN توسط سیستم صادر نشد');
        return;
      }

      _setPending(true);
      final token = ++_pendingToken;
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _pendingToken == token && _pendingTarget == true) {
          setState(() => _pendingTarget = null);
        }
      });

      await savePersistentData();
      final finalConfig = buildCustomizedConfig(target.fullJsonConfig);
      await flutterV2ray.startV2Ray(
        remark: target.remark,
        config: finalConfig,
        proxyOnly: false,
        blockedApps: bypassApps.isEmpty ? null : bypassApps.toList(),
        bypassSubnets: null,
      );
      started = true;
    } catch (e) {
      showSnack('خطا در برقراری اتصال: $e');
    } finally {
      _vpnBusy = false;
      if (wantConnect && !started && _pendingTarget == true) _setPending(null);
    }
  }

  Future<void> reconnectIfNeeded() async {
    if (!isConnected && !isConnecting) return;
    await flutterV2ray.stopV2Ray();
    for (var i = 0; i <= 24 && _connState != 'DISCONNECTED'; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await toggleVpn();
  }

  Future<int> _measureThroughTunnel() async {
    final url = Uri.tryParse(pingTestUrl.trim());
    if (url == null || (url.scheme != 'https' && url.scheme != 'http')) {
      return -1;
    }

    final timeout = Duration(seconds: pingProxyTimeoutSec);
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 10)
      ..maxConnectionsPerHost = 1;
    final samples = <int>[];
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final stopwatch = Stopwatch()..start();
          final request = await client.getUrl(url).timeout(timeout);
          request.persistentConnection = true;
          request.headers.set(HttpHeaders.acceptHeader, '*/*');
          final response = await request.close().timeout(timeout);
          stopwatch.stop();
          final elapsed = stopwatch.elapsedMilliseconds;
          final validStatus = response.statusCode == HttpStatus.ok ||
              response.statusCode == HttpStatus.noContent;
          final keepAlive = response.persistentConnection;
          await response.drain<void>();
          if (validStatus) samples.add(elapsed);
          if (attempt == 0 && !keepAlive) {
            break;
          }
        } catch (_) {
          break;
        }
      }
    } finally {
      client.close(force: true);
    }

    if (samples.length >= 2) return samples[1];
    return samples.isEmpty ? -1 : samples.first;
  }

  Future<int> _measureViaProxy(ServerItem server) async {
    if (isConnected) {
      if (server.id != selectedServerId) return -1;
      final viaTunnel = await _measureThroughTunnel();
      if (viaTunnel > 0) return viaTunnel;
      try {
        final ms = await flutterV2ray
            .getConnectedServerDelay(url: pingTestUrl)
            .timeout(Duration(seconds: pingProxyTimeoutSec));
        return ms > 0 ? ms : -1;
      } catch (_) {
        return -1;
      }
    }
    final raw = server.fullJsonConfig;
    final cfg = pingBypassRouting
        ? buildCustomizedConfig(raw)
        : buildLightweightPingConfig(raw);
    final timeout = Duration(seconds: pingProxyTimeoutSec);
    final attempts = pingBestOfTwo ? 2 : 1;

    final samples = <int>[];
    for (var i = 0; i < attempts; i++) {
      try {
        final ms = await flutterV2ray
            .getServerDelay(config: cfg)
            .timeout(timeout);
        if (ms > 0) samples.add(ms);
      } catch (_) {}
    }
    if (samples.isEmpty) return -1;
    samples.sort();
    return samples.first;
  }

  Future<void> pingSingleServer(
    ServerItem server, {
    PingMode? mode,
    bool save = true,
  }) async {
    final testMode = mode ?? selectedPingMode;
    final key = testMode.name;
    if (!mounted || server.busyPings.contains(key)) return;

    setState(() => server.busyPings.add(key));

    var result = -1;
    try {
      result = await _measureViaProxy(server);
      if (result > 0) await _resolveServerCountry(server);
    } catch (_) {
      result = -1;
    } finally {
      server.busyPings.remove(key);
      server.pings[key] = result;
      if (mounted) setState(() {});
      if (save) await savePersistentData();
    }
  }

  static const int kPingConcurrencyMin = 2;
  static const int kPingConcurrencyMax = 8;
  static const int kPingConcurrencyStart = 4;

  Future<void> testAllPings() async {
    if (isTestingAll || servers.isEmpty) return;
    final mode = selectedPingMode;
    final queue = isConnected
        ? <ServerItem>[if (selectedServer != null) selectedServer!]
        : List<ServerItem>.from(servers);
    if (isConnected) {
      showSnack('هنگام اتصال فقط سرور فعال تست می‌شود');
    }
    if (queue.isEmpty) return;

    setState(() {
      isTestingAll = true;
      pingTestsCompleted = 0;
      pingTestsTotal = queue.length;
    });

    var concurrency = min(kPingConcurrencyStart, queue.length);
    var offset = 0;
    try {
      while (mounted && offset < queue.length) {
        final end = min(offset + concurrency, queue.length);
        final batch = queue.sublist(offset, end);
        await Future.wait([
          for (final server in batch)
            pingSingleServer(server, mode: mode, save: false),
        ]);

        final successful = batch
            .where((server) => (server.pingFor(mode) ?? -1) > 0)
            .length;
        final successRatio = batch.isEmpty ? 0.0 : successful / batch.length;
        offset = end;
        if (mounted) {
          setState(() => pingTestsCompleted = offset);
        }

        if (successRatio >= 0.80 && concurrency < kPingConcurrencyMax) {
          concurrency++;
        } else if (successRatio <= 0.40 &&
            concurrency > kPingConcurrencyMin) {
          concurrency--;
        }
      }
    } finally {
      if (mounted) setState(() => isTestingAll = false);
      await savePersistentData();
    }
  }
Future<void> checkForXrayCoreUpdate() async {
    if (isCheckingUpdate) return;
    setState(() => isCheckingUpdate = true);
    showSnack('در حال بررسی آخرین نسخه هسته Xray...');

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(
        Uri.parse(
            'https://api.github.com/repos/XTLS/Xray-core/releases/latest'),
      );
      req.headers.set('User-Agent', 'SHIN-Updater');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await utf8.decoder.bind(resp).join();
      final data = jsonDecode(body);
      final latestTag = (data['tag_name'] ?? 'نامشخص').toString();
      final publishedAt =
          (data['published_at'] ?? '').toString().split('T').first;

      if (!mounted) return;
      _infoSheet(
        icon: Icons.memory_rounded,
        color: const Color(0xFF10B981),
        title: 'وضعیت هسته Xray',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('نسخهٔ فعلی', coreVersion),
            _kv('آخرین نسخهٔ رسمی', '$latestTag ($publishedAt)'),
            const SizedBox(height: 6),
            const Text(
              'هسته Xray به همراه کتابخانه کامپایل شده و آماده بهره‌برداری است.',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
            ),
          ],
        ),
        actions: (ctx) => [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('متوجه شدم'),
          ),
        ],
      );
    } catch (e) {
      showSnack('خطا در استعلام نسخه هسته: $e');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => isCheckingUpdate = false);
    }
  }

  List<int> _verParts(String v) {
    return v
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
  }

  bool _isNewer(String remote, String local) {
    final a = _verParts(remote);
    final b = _verParts(local);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<void> checkForAppUpdate({bool silent = false}) async {
    if (isCheckingUpdate) return;
    setState(() => isCheckingUpdate = true);

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(updateRepoUrl.trim()));
      req.headers.set('User-Agent', 'SHIN-Updater');
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await utf8.decoder.bind(resp).join();
      final data = jsonDecode(body);
      if (data is! Map) throw 'پاسخ نامعتبر از سرور';

      final tag =
          (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), '');
      final notes = (data['body'] ?? '').toString();

      var apk = '';
      final assets = data['assets'];
      if (assets is List) {
        for (final a in assets) {
          if (a is! Map) continue;
          final name = (a['name'] ?? '').toString();
          if (!name.endsWith('.apk')) continue;
          apk = (a['browser_download_url'] ?? '').toString();
          break;
        }
      }

      if (!mounted) return;
      final newer = tag.isNotEmpty && _isNewer(tag, kAppVersion);
      setState(() {
        availableVersion = newer ? tag : '';
        availableApkUrl = apk;
        availableChangelog = notes;
      });

      if (!silent) {
        if (newer) {
          _showUpdateSheet();
        } else {
          showSnack('برنامه به‌روز است ($kAppVersion)');
        }
      }
    } catch (_) {
      if (!silent) showSnack('بررسی بروزرسانی ناموفق بود');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => isCheckingUpdate = false);
    }
  }

  void _showUpdateSheet() {
    _infoSheet(
      icon: Icons.system_update_rounded,
      color: const Color(0xFF3B82F6),
      title: 'نسخهٔ جدید $availableVersion',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _kv('نسخهٔ فعلی', kAppVersion),
          if (availableChangelog.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(
                  availableChangelog,
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: (ctx) => [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('بعداً'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          label: const Text('دانلود و نصب'),
          onPressed: () {
            Navigator.pop(ctx);
            _downloadAndInstall();
          },
        ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    if (availableApkUrl.isEmpty) {
      showSnack('فایل نصبی این نسخه پیدا نشد');
      return;
    }
    final text = ValueNotifier<String>('در حال دانلود...');
    final value = ValueNotifier<double?>(null);
    final client = HttpClient();
    final version = availableVersion.isEmpty ? 'latest' : availableVersion;
    NavigatorState? sheetNav;

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        builder: (ctx) {
          sheetNav = Navigator.of(ctx);
          return PopScope(
            canPop: false,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: ValueListenableBuilder<double?>(
                  valueListenable: value,
                  builder: (_, v, __) => ValueListenableBuilder<String>(
                    valueListenable: text,
                    builder: (_, t, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('دانلود نسخهٔ $version',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: v, minHeight: 8),
                        const SizedBox(height: 10),
                        Text(t,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is File) await f.delete();
        }
      } else {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/shin-$version.apk');

      final req = await client.getUrl(Uri.parse(availableApkUrl));
      req.followRedirects = true;
      req.maxRedirects = 5;
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw 'کد پاسخ سرور: ${resp.statusCode}';
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        value.value = total > 0 ? received / total : null;
        text.value = total > 0
            ? '${(received / total * 100).toStringAsFixed(0)}%  •  '
                '${_fmtBytes(received)} از ${_fmtBytes(total)}'
            : '${_fmtBytes(received)} دانلود شده';
      }
      await sink.close();
      if (total > 0 && received != total) {
        throw 'دانلود کامل نشد';
      }

      if (sheetNav != null && sheetNav!.canPop()) {
        sheetNav!.pop();
      }
      final result = await kQuickControlsChannel
          .invokeMethod<String>('installApk', {'path': file.path});
      if (result == 'permission') {
        showSnack('اجازهٔ نصب از این منبع را بدهید و دوباره تلاش کنید');
      }
    } catch (e) {
      if (sheetNav != null && sheetNav!.canPop()) {
        sheetNav!.pop();
      }
      showSnack('دانلود ناموفق بود: $e');
    } finally {
      client.close(force: true);
      text.dispose();
      value.dispose();
    }
  }

  Widget _updateBanner() {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'نسخهٔ جدید $availableVersion موجود است',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (downloadProgress != null)
            LinearProgressIndicator(
              value: downloadProgress == 0 ? null : downloadProgress,
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _downloadAndInstall,
                    child: const Text('دانلود و نصب'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => availableVersion = ''),
                  child: const Text('بعداً'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> updateSubscription(
    SubscriptionItem sub, {
    bool silent = false,
  }) async {
    if (sub.isUpdating) return;
    while (_subUpdateMutex) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _subUpdateMutex = true;

    try {
      if (!mounted) return;
      setState(() {
        sub.isUpdating = true;
        sub.lastError = null;
      });

      ImportReport? best;
      FetchResult? bestFetch;
      String? networkError;

      final candidateUrls =
          resolveSubscriptionCandidateUrls(sub.url, sub.fallbackUrl);

      outerLoop:
      for (final targetUrl in candidateUrls) {
        for (final ua in kUserAgents) {
          final res = await fetchSubscription(targetUrl, ua, hwid);
          if (res.error != null) {
            networkError = res.error;
            break;
          }
          if (res.status != 200) {
            best ??= ImportReport()..httpStatus = res.status;
            best.httpStatus = res.status;
            continue;
          }
          final report =
              buildImport(res.body, subId: sub.id, subName: sub.name);
          report.httpStatus = res.status;
          if (best == null ||
              report.added > best.added ||
              best.httpStatus != 200) {
            best = report;
            bestFetch = res;
          }
          if (report.added > 0 &&
              report.failed == 0 &&
              report.unsupported.isEmpty) {
            break outerLoop;
          }
        }
      }

      if (!mounted) return;

      if (networkError != null && (best == null || best.added == 0)) {
        setState(() {
          sub.isUpdating = false;
          sub.lastError = 'خطای شبکه یا عدم دسترسی به لینک';
        });
        if (!silent) showSnack('خطا در دریافت سابسکریپشن «${sub.name}» ❌');
        return;
      }

      final report = best ?? ImportReport();

      if (report.added > 0) {
        final prev = selectedServer;
        final prevWasInThisSub = prev != null && prev.subId == sub.id;
        final prevRawUrl = prev?.rawUrl;
        final prevRemark = prev?.remark;

        servers.removeWhere((s) => s.subId == sub.id);
        servers.addAll(report.servers);

        if (prevWasInThisSub) {
          ServerItem? matched;
          if (prevRawUrl != null && prevRawUrl.isNotEmpty) {
            for (final s in report.servers) {
              if (s.rawUrl == prevRawUrl) {
                matched = s;
                break;
              }
            }
          }
          if (matched == null && prevRemark != null) {
            for (final s in report.servers) {
              if (s.remark == prevRemark) {
                matched = s;
                break;
              }
            }
          }
          if (matched != null) {
            selectedServerId = matched.id;
          }
        }
        if (!servers.any((s) => s.id == selectedServerId) &&
            servers.isNotEmpty) {
          selectedServerId = servers.first.id;
        }
      } else {
        sub.lastError = report.httpStatus != 200 && report.httpStatus != 0
            ? 'کد وضعیت سرور: ${report.httpStatus}'
            : 'هیچ سروری در پاسخ یافت نشد';
      }

      if (bestFetch != null) {
        final fallbackHeader = bestFetch.headers['fallback-url'] ??
            bestFetch.headers['x-fallback-url'];
        if (fallbackHeader != null && fallbackHeader.startsWith('http')) {
          sub.fallbackUrl = fallbackHeader.trim();
        }

        final info = bestFetch.headers['subscription-userinfo'];
        if (info != null) {
          sub.usedBytes = 0;
          for (final part in info.split(';')) {
            final kv = part.trim().split('=');
            if (kv.length != 2) continue;
            final value = double.tryParse(kv[1].trim())?.toInt() ?? 0;
            switch (kv[0].trim().toLowerCase()) {
              case 'upload':
              case 'download':
                sub.usedBytes += value;
                break;
              case 'total':
                sub.totalBytes = value;
                break;
              case 'expire':
                sub.expireSec = value;
                break;
            }
          }
        }
        final title = bestFetch.headers['profile-title'];
        if (title != null && title.isNotEmpty && sub.autoName) {
          var t = title.trim();
          if (t.toLowerCase().startsWith('base64:')) {
            t = LinkParser.decodeBase64Loose(t.substring(7)) ?? t;
          }
          if (t.isNotEmpty) {
            sub.name = t;
            for (final s in servers.where((s) => s.subId == sub.id)) {
              s.subName = t;
            }
          }
        }
      }

      setState(() {
        sub.isUpdating = false;
        if (report.added > 0) {
          sub.serverCount = report.added;
          sub.updatedAt = DateTime.now().millisecondsSinceEpoch;
        }
      });
      await savePersistentData();

      if (silent) return;
      if (report.hasProblems) {
        _showReportSheet(sub.name, report);
      } else {
        showSnack(
            'اشتراک «${sub.name}» بروزرسانی شد (${report.added} سرور) ✅');
      }
    } finally {
      _subUpdateMutex = false;
    }
  }

  Future<void> updateAllSubscriptions() async {
    if (subscriptions.isEmpty) {
      showSnack('هیچ سابسکریپشنی ثبت نشده است!');
      return;
    }
    for (final sub in List<SubscriptionItem>.from(subscriptions)) {
      await updateSubscription(sub);
    }
  }

  Future<void> _autoUpdateOldSubscriptions() async {
    if (!autoUpdateSubs) return;
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 6))
        .millisecondsSinceEpoch;
    for (final sub in List<SubscriptionItem>.from(subscriptions)) {
      if (sub.updatedAt <= cutoff) {
        await updateSubscription(sub, silent: true);
      }
    }
  }

  Future<bool> _applyRoutingText(String rawText) async {
    final parsed = parseRoutingInput(rawText);
    if (parsed == null) return false;
    _applySetting(() {
      customDirectIps = parsed.directIps;
      customDirectDomains = parsed.directDomains;
      customRoutingName = parsed.name;
      bypassIran = true;
    });
    await savePersistentData();
    await reconnectIfNeeded();
    showSnack(
      'قوانین روتینگ ذخیره شد (${parsed.directIps.length} رنج IP و ${parsed.directDomains.length} دامنه) ✅',
    );
    return true;
  }

  Future<void> importFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      showSnack('کلیپ‌بورد خالی است! 📋');
      return;
    }
    await processInput(text);
  }

  Future<void> processInput(
    String input, {
    String? name,
    String? fallbackUrl,
  }) async {
    final text = input.trim();
    if (text.isEmpty) return;

    if (text.toLowerCase().startsWith('happ://routing/')) {
      final ok = await _applyRoutingText(text);
      if (!ok) showSnack('فرمت قوانین روتینگ معتبر نیست');
      return;
    }

    final isUrl =
        RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(text);
    if (isUrl) {
      final existing = subscriptions.where((s) => s.url == text);
      if (existing.isNotEmpty) {
        showSnack('این اشتراک قبلاً ثبت شده؛ در حال بروزرسانی...');
        await updateSubscription(existing.first);
        return;
      }

      var subName = (name ?? '').trim();
      var auto = false;
      if (subName.isEmpty) {
        final frag = Uri.tryParse(text)?.fragment ?? '';
        subName = frag.isNotEmpty
            ? LinkParser.safeDecode(frag)
            : 'اشتراک ${subscriptions.length + 1}';
        auto = frag.isEmpty;
      }

      final sub = SubscriptionItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: subName,
        url: text,
        fallbackUrl: (fallbackUrl ?? '').trim(),
        autoName: auto,
      );
      setState(() => subscriptions.add(sub));
      await savePersistentData();
      await updateSubscription(sub);
      return;
    }

    final report = buildImport(text, subId: 'manual', subName: 'دستی');
    final existingUrls = servers
        .where((s) => s.subId == 'manual')
        .map((s) => s.rawUrl)
        .toSet();
    final fresh = report.servers
        .where((s) => s.rawUrl.isEmpty || !existingUrls.contains(s.rawUrl))
        .toList();

    if (fresh.isNotEmpty) {
      setState(() {
        servers.addAll(fresh);
        if (selectedServerId.isEmpty) selectedServerId = fresh.first.id;
      });
      await savePersistentData();
    }

    if (report.failed > 0 ||
        report.unsupported.isNotEmpty ||
        report.added == 0) {
      _showReportSheet('افزودن دستی', report);
    } else if (fresh.isEmpty) {
      showSnack('این سرورها قبلاً در لیست وجود داشتند.');
    } else {
      showSnack('${fresh.length} سرور جدید اضافه شد ✅');
    }
  }
void _showCustomRoutingSheet() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHeader(
                  Icons.alt_route_rounded,
                  const Color(0xFF10B981),
                  'قوانین روتینگ سفارشی (بای‌پس مستقیم)',
                  customDirectIps.isEmpty && customDirectDomains.isEmpty
                      ? 'فعلاً قانونی وارد نشده است'
                      : 'فعال: ${customDirectIps.length} رنج IP و ${customDirectDomains.length} دامنه',
                ),
                const SizedBox(height: 10),
                const Text(
                  'متن happ://routing/add/... یا لیست CIDR آی‌پی‌ها و دامنه‌ها را اینجا بچسبانید تا بدون عبور از فیلترشکن و مستقیم باز شوند.',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 7,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'happ://routing/add/eyJ... یا 2.144.0.0/14',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: 'چسباندن از کلیپ‌بورد',
                      onPressed: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        if (d?.text != null) {
                          controller.text = d!.text!.trim();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (customDirectIps.isNotEmpty ||
                        customDirectDomains.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('پاک کردن'),
                          onPressed: () async {
                            _applySetting(() {
                              customDirectIps.clear();
                              customDirectDomains.clear();
                              customRoutingName = '';
                            });
                            await savePersistentData();
                            await reconnectIfNeeded();
                            if (ctx.mounted) Navigator.pop(ctx);
                            showSnack('قوانین روتینگ سفارشی پاک شدند');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('ذخیره و اعمال'),
                        onPressed: () async {
                          final raw = controller.text.trim();
                          if (raw.isEmpty) return;
                          final ok = await _applyRoutingText(raw);
                          if (ok) {
                            if (ctx.mounted) Navigator.pop(ctx);
                          } else {
                            showSnack('متن واردشده قابل شناسایی نبود');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReportSheet(String title, ImportReport r) {
    if (!mounted) return;
    final lines = <String>[];
    if (r.added > 0) lines.add('✅ ${r.added} سرور با موفقیت خوانده شد');
    if (r.failed > 0) {
      lines.add('⚠️ ${r.failed} لینک ناقص بود یا قابل پردازش نبود');
    }
    if (r.unsupported.isNotEmpty) {
      final parts = r.unsupported.entries
          .map((e) => '${e.key} (${e.value})')
          .join('، ');
      lines.add('🚫 پروتکل خارج از هسته Xray: $parts');
    }
    if (r.looksLikeHtml) {
      lines.add(
          '🌐 سرور یک صفحهٔ وب (HTML) برگرداند. لینک اشتباه است یا نیاز به ثبت HWID دارد.');
    }
    if (r.looksLikeClash) {
      lines.add(
          '📄 خروجی به فرمت Clash است. لطفاً لینک استاندارد V2Ray/Xray یا Base64 وارد کنید.');
    }
    if (r.httpStatus != 0 && r.httpStatus != 200 && r.added == 0) {
      lines.add('❌ کد پاسخ سرور: ${r.httpStatus}');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(Icons.fact_check_rounded, const Color(0xFF3B82F6),
                  'گزارش پردازش', title),
              const SizedBox(height: 14),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                      Text(l, style: const TextStyle(fontSize: 13, height: 1.6)),
                ),
              if (r.rawPreview.isNotEmpty && r.added == 0) ...[
                const SizedBox(height: 6),
                const Text('پیش‌نمایش پاسخ دریافتی:',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    r.rawPreview,
                    textDirection: TextDirection.ltr,
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('متوجه شدم'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSheet() {
    final textCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final fallbackCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.add_link_rounded,
                          color: Color(0xFF3B82F6)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'افزودن سرور، اشتراک یا روتینگ',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'لینک vless، vmess، trojan، ss، socks، لینک اشتراک، JSON یا قوانین happ://routing/add/... را بچسبانید.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: textCtrl,
                  minLines: 3,
                  maxLines: 6,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'vless://... یا https://... یا happ://routing/...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: 'چسباندن از کلیپ‌بورد',
                      onPressed: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        if (d?.text != null) textCtrl.text = d!.text!.trim();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('تنظیمات بیشتر',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نام دلخواه (اختیاری)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: fallbackCtrl,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'لینک جایگزین (اختیاری)',
                        hintText: 'https://backup-domain.com/sub/...',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('افزودن'),
                  onPressed: () {
                    final t = textCtrl.text;
                    final n = nameCtrl.text;
                    final fb = fallbackCtrl.text;
                    if (t.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    processInput(t, name: n, fallbackUrl: fb);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _infoSheet({
    required IconData icon,
    required Color color,
    required String title,
    required Widget body,
    required List<Widget> Function(BuildContext ctx) actions,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(icon, color, title),
              const SizedBox(height: 16),
              body,
              const SizedBox(height: 18),
              Row(
                children: [
                  for (var i = 0; i < actions(ctx).length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: actions(ctx)[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader(IconData icon, Color color, String title,
      [String? subtitle]) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  void _showJsonEditorModal(ServerItem server) {
    String prettyJson = server.fullJsonConfig;
    try {
      final decoded = jsonDecode(server.fullJsonConfig);
      prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}

    final jsonCtrl = TextEditingController(text: prettyJson);
    final remarkCtrl = TextEditingController(text: server.remark);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(Icons.data_object_rounded, const Color(0xFF8B5CF6),
                  'کانفیگ سرور', 'ویرایش JSON هستهٔ Xray'),
              const SizedBox(height: 14),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: 'نام سرور'),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 260,
                child: TextField(
                  controller: jsonCtrl,
                  maxLines: null,
                  expands: true,
                  textDirection: TextDirection.ltr,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('کپی'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonCtrl.text));
                        showSnack('کانفیگ JSON کپی شد');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('ذخیره'),
                      onPressed: () {
                        try {
                          final parsed = jsonDecode(jsonCtrl.text);
                          if (parsed is! Map) {
                            throw const FormatException(
                                'JSON باید یک شیء باشد');
                          }
                          setState(() {
                            server.remark = remarkCtrl.text.trim().isEmpty
                                ? server.remark
                                : remarkCtrl.text.trim();
                            server.fullJsonConfig = jsonEncode(parsed);
                          });
                          savePersistentData();
                          Navigator.pop(ctx);
                          showSnack('تغییرات کانفیگ ذخیره شد');
                        } catch (e) {
                          showSnack('خطای سینتکس JSON: $e');
                        }
                      },
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

  void showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: _buildHomeTab()),
    );
  }

  String _fmtSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  final Map<String, String> _countryByIp = {};

  Future<void> _resolveServerCountry(ServerItem server) async {
    if (server.countryCode.isNotEmpty) return;
    final ep = extractServerEndpoint(server.fullJsonConfig);
    if (ep == null) return;
    try {
      final addr = await InternetAddress.lookup(ep.host)
          .timeout(const Duration(seconds: 4));
      if (addr.isEmpty) return;
      final ip = addr.first.address;
      var code = _countryByIp[ip] ?? '';
      if (code.isEmpty) {
        final info = await _fetchJson('https://api.country.is/$ip');
        code = (info?['country'] ?? '').toString();
        if (code.isNotEmpty) _countryByIp[ip] = code;
      }
      if (code.isNotEmpty) server.countryCode = code;
    } catch (_) {}
  }

  Widget _speedItem(
      IconData icon, Color color, String speedText, String totalText) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              speedText,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'کل: $totalText',
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _bgTop =>
      _isDark ? const Color(0xFF0B1033) : const Color(0xFFF4F5F8);
  Color get _bgBottom =>
      _isDark ? const Color(0xFF151B4D) : const Color(0xFFE9ECF2);
  Color get _cardSurface =>
      _isDark ? const Color(0xFF181E4B).withOpacity(0.88) : Colors.white;
  Color get _cardBorder =>
      _isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E5EC);

  Widget _liveStatsCard() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: _statusNotifier,
      builder: (context, st, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 15, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text(
                        st.duration,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: _checkRealIp,
                    child: Row(
                      children: [
                        if (_isCheckingIp)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        else if (_currentIp.isNotEmpty)
                          Text(
                            '${flagOf(_currentIpCountry)} $_currentIp',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w600),
                          )
                        else
                          const Text('تست IP',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SpeedGraphPainter(
                    dl: _dlHistory,
                    ul: _ulHistory,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _speedItem(
                      Icons.arrow_downward_rounded,
                      const Color(0xFF22C55E),
                      _fmtSpeed(st.downloadSpeed),
                      _fmtBytes(st.download),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: _cardBorder,
                  ),
                  Expanded(
                    child: _speedItem(
                      Icons.arrow_upward_rounded,
                      const Color(0xFFA855F7),
                      _fmtSpeed(st.uploadSpeed),
                      _fmtBytes(st.upload),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.grey,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).dividerColor),
          ],
        ],
      ),
    );
  }

  Widget _settingsSwitch({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
      value: value,
      onChanged: (v) {
        onChanged(v);
        savePersistentData();
      },
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }

  void Function()? _settingsRebuild;

  void _applySetting(VoidCallback change) {
    setState(change);
    _settingsRebuild?.call();
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => StatefulBuilder(
            builder: (ctx, setLocal) {
              _settingsRebuild = () => setLocal(() {});
              return Directionality(
                textDirection: TextDirection.rtl,
                child: _buildSettingsTab(),
              );
            },
          ),
        ))
        .then((_) => _settingsRebuild = null);
  }

  void _openAdvancedSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: _buildAdvancedSettingsPage(setLocal),
          );
        },
      ),
    ));
  }

  void _showAddChooser() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('اسکن QR Code با دوربین'),
                subtitle: const Text('اسکن بارکد سرور یا اشتراک از صفحه دیگر'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanQrFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_rounded),
                title: const Text('وارد کردن از کلیپ‌بورد'),
                subtitle: const Text(
                    'لینک سرور، اشتراک یا روتینگ کپی‌شده را اضافه کن'),
                onTap: () {
                  Navigator.pop(ctx);
                  importFromClipboard();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('افزودن دستی'),
                subtitle: const Text('لینک یا JSON را خودت وارد کن'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeHeader() {
    final iconColor = _isDark ? Colors.white : const Color(0xFF1E293B);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              IconButton(
                icon: Icon(Icons.add_rounded, size: 30, color: iconColor),
                tooltip: 'افزودن سرور یا اشتراک',
                onPressed: _showAddChooser,
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.mail_rounded,
                        size: 22, color: iconColor.withOpacity(0.9)),
                    tooltip: 'پیام‌ها و اعلان‌ها',
                    onPressed: _showInboxSheet,
                  ),
                  if (_hasUnreadMessages || availableVersion.isNotEmpty)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            children: [
              IconButton(
                icon: Icon(Icons.settings_rounded, size: 28, color: iconColor),
                tooltip: 'تنظیمات',
                onPressed: _openSettings,
              ),
              IconButton(
                icon: Icon(Icons.cell_tower_rounded,
                    size: 20, color: iconColor.withOpacity(0.75)),
                tooltip: 'پروفایل اپراتورها',
                onPressed: _showCarrierPresetSheet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<ServerItem> _orderServers(List<ServerItem> list, {bool sort = false}) {
    final copy = List<ServerItem>.from(list);
    int rank(ServerItem s) {
      final p = s.pingFor(PingMode.real);
      if (p == null) return 2;
      if (p <= 0) return 3;
      return 1;
    }

    copy.sort((a, b) {
      final fa = _favoriteServerIds.contains(a.id) ? 0 : 1;
      final fb = _favoriteServerIds.contains(b.id) ? 0 : 1;
      if (fa != fb) return fa.compareTo(fb);
      if (!sort) return 0;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (a.pingFor(PingMode.real) ?? 0)
          .compareTo(b.pingFor(PingMode.real) ?? 0);
    });
    return copy;
  }

  Widget _usageBar(double ratio, String text, ColorScheme scheme) {
    final color = ratio > 0.9 ? Colors.redAccent : scheme.primary;
    return Container(
      height: 22,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withOpacity(0.08),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio,
              heightFactor: 1,
              child: Container(color: color.withOpacity(0.24)),
            ),
          ),
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _groupSection({
    required String id,
    required String title,
    SubscriptionItem? sub,
    required List<ServerItem> servers,
  }) {
    return RepaintBoundary(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: _groupSectionBody(
          id: id,
          title: title,
          sub: sub,
          servers: servers,
        ),
      ),
    );
  }

  Widget _groupSectionBody({
    required String id,
    required String title,
    SubscriptionItem? sub,
    required List<ServerItem> servers,
  }) {
    final collapsed = _collapsedGroups.contains(id);
    final sorted = _sortedGroups.contains(id);
    final byCountry = _countryGroups.contains(id);
    final testing = _testingGroups.contains(id);
    final scheme = Theme.of(context).colorScheme;
    final divider = _cardBorder;
    final used = sub?.usedBytes ?? 0;
    final total = sub?.totalBytes ?? 0;
    final unlimited = total <= 0;
    final ratio = unlimited ? 1.0 : (used / total).clamp(0.0, 1.0).toDouble();
    final usageText =
        unlimited ? 'نامحدود' : '${_fmtBytes(used)} / ${_fmtBytes(total)}';
    var expiry = 'بدون انقضا';
    if (sub != null && sub.expireSec > 0) {
      final days = DateTime.fromMillisecondsSinceEpoch(sub.expireSec * 1000)
          .difference(DateTime.now())
          .inDays;
      expiry = days >= 0 ? '$days روز' : 'منقضی';
    }
    final ordered = _orderServers(servers, sort: sorted);

    void toggleCollapsed() {
      setState(() {
        if (collapsed) {
          _collapsedGroups.remove(id);
        } else {
          _collapsedGroups.add(id);
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: divider),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: collapsed ? 'باز کردن' : 'بستن',
                    icon: Icon(collapsed
                        ? Icons.chevron_left_rounded
                        : Icons.expand_more_rounded),
                    onPressed: toggleCollapsed,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: toggleCollapsed,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            sub == null
                                ? '${servers.length} سرور'
                                : '${servers.length} سرور  •  ${fmtAgo(sub.updatedAt)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (testing)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'تست پینگ این بخش',
                      icon: const Icon(Icons.speed_rounded, size: 20),
                      onPressed: () => testGroupPings(id, servers),
                    ),
                  if (sub != null)
                    sub.isUpdating
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'بروزرسانی اشتراک',
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            onPressed: () => updateSubscription(sub),
                          ),
                  PopupMenuButton<String>(
                    tooltip: 'گزینه‌ها',
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (v) {
                      if (v == 'sort') {
                        setState(() {
                          if (sorted) {
                            _sortedGroups.remove(id);
                          } else {
                            _sortedGroups.add(id);
                          }
                        });
                      }
                      if (v == 'country') {
                        setState(() {
                          if (byCountry) {
                            _countryGroups.remove(id);
                          } else {
                            _countryGroups.add(id);
                          }
                        });
                        savePersistentData();
                        if (!byCountry) _ensureCountries(servers);
                      }
                      if (sub != null && v == 'qr') {
                        _showQrShareSheet(
                          'QR Code اشتراک',
                          sub.name,
                          sub.url,
                        );
                      }
                      if (sub != null && v == 'copy') {
                        Clipboard.setData(ClipboardData(text: sub.url));
                        showSnack('لینک اشتراک کپی شد');
                      }
                      if (sub != null && v == 'delete') {
                        setState(() {
                          this.servers.removeWhere((s) => s.subId == sub.id);
                          subscriptions.removeWhere((s) => s.id == sub.id);
                          if (selectedGroupFilter == sub.id) {
                            selectedGroupFilter = 'ALL';
                          }
                          if (!this
                              .servers
                              .any((s) => s.id == selectedServerId)) {
                            selectedServerId = this.servers.isNotEmpty
                                ? this.servers.first.id
                                : '';
                          }
                        });
                        savePersistentData();
                      }
                      if (sub == null && v == 'delete_manual') {
                        setState(() {
                          this.servers.removeWhere((s) => s.subId == 'manual');
                          if (!this
                              .servers
                              .any((s) => s.id == selectedServerId)) {
                            selectedServerId = this.servers.isNotEmpty
                                ? this.servers.first.id
                                : '';
                          }
                        });
                        savePersistentData();
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'sort',
                        child: Text(sorted
                            ? 'بازگشت به ترتیب اولیه'
                            : 'مرتب‌سازی بر اساس پینگ'),
                      ),
                      PopupMenuItem<String>(
                        value: 'country',
                        child: Text(byCountry
                            ? 'گروه‌بندی: بدون کشور'
                            : 'گروه‌بندی: بر اساس کشور'),
                      ),
                      if (sub != null) ...[
                        const PopupMenuItem<String>(
                          value: 'qr',
                          child: Text('نمایش QR Code اشتراک'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'copy',
                          child: Text('کپی لینک'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('حذف اشتراک'),
                        ),
                      ] else ...[
                        const PopupMenuItem<String>(
                          value: 'delete_manual',
                          child: Text('حذف همه سرورهای دستی'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (sub != null)
              Container(
                color: scheme.primary.withOpacity(0.05),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Row(
                  children: [
                    Expanded(child: _usageBar(ratio, usageText, scheme)),
                    const SizedBox(width: 10),
                    Text(
                      expiry,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (!collapsed) ...[
              Divider(height: 1, color: divider),
              if (byCountry)
                _countryBlocks(servers, sorted)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < ordered.length; i++) ...[
                      _serverTile(ordered[i]),
                      if (i < ordered.length - 1)
                        Divider(height: 1, color: divider),
                    ],
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
Future<void> _ensureCountries(List<ServerItem> list) async {
    final missing = list.where((x) => x.countryCode.isEmpty).toList();
    if (missing.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (mounted && next < missing.length) {
        final server = missing[next++];
        await _resolveServerCountry(server);
        if (server.countryCode.isEmpty) {
          server.countryCode = detectCountryFromText(server.remark);
        }
        if (mounted) setState(() {});
      }
    }

    await Future.wait([
      for (var i = 0; i < min(kPingConcurrencyMax, missing.length); i++) worker(),
    ]);
    await savePersistentData();
  }

  Widget _countryBlocks(List<ServerItem> list, bool sorted) {
    final divider = _cardBorder;
    final buckets = <String, List<ServerItem>>{};
    for (final server in list) {
      final code =
          server.countryCode.isEmpty ? '??' : server.countryCode.toUpperCase();
      buckets.putIfAbsent(code, () => <ServerItem>[]).add(server);
    }
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        if (a == '??') return 1;
        if (b == '??') return -1;
        return (kCountryNames[a] ?? a).compareTo(kCountryNames[b] ?? b);
      });

    final children = <Widget>[];
    for (final key in keys) {
      final items = _orderServers(buckets[key]!, sort: sorted);
      children.add(Container(
        color: _isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            Text(flagOf(key), style: const TextStyle(fontSize: 17)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                key == '??' ? 'نامشخص' : (kCountryNames[key] ?? key),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Text('${items.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ));
      for (var i = 0; i < items.length; i++) {
        children.add(_serverTile(items[i]));
        if (i < items.length - 1) {
          children.add(Divider(height: 1, color: divider));
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Future<void> testGroupPings(String id, List<ServerItem> list) async {
    if (_testingGroups.contains(id)) return;
    final queue = isConnected
        ? list.where((s) => s.id == selectedServerId).toList()
        : List<ServerItem>.from(list);
    if (queue.isEmpty) return;

    setState(() => _testingGroups.add(id));
    var concurrency = min(kPingConcurrencyStart, queue.length);
    var offset = 0;
    try {
      while (mounted && offset < queue.length) {
        final end = min(offset + concurrency, queue.length);
        final batch = queue.sublist(offset, end);
        await Future.wait([
          for (final server in batch) pingSingleServer(server, save: false),
        ]);
        final successful = batch
            .where((server) => (server.pingFor(selectedPingMode) ?? -1) > 0)
            .length;
        final successRatio = batch.isEmpty ? 0.0 : successful / batch.length;
        offset = end;
        if (successRatio >= 0.80 && concurrency < kPingConcurrencyMax) {
          concurrency++;
        } else if (successRatio <= 0.40 &&
            concurrency > kPingConcurrencyMin) {
          concurrency--;
        }
      }
    } finally {
      if (mounted) setState(() => _testingGroups.remove(id));
      await savePersistentData();
    }
  }

  Widget _buildServerFilterBar() {
    final codes = <String>{};
    for (final s in servers) {
      final code = s.countryCode.trim().toUpperCase();
      if (code.length == 2 && code != '??') codes.add(code);
    }
    final sortedCodes = codes.toList()
      ..sort((a, b) => (kCountryNames[a] ?? a).compareTo(kCountryNames[b] ?? b));

    final failedCount = servers.where((s) {
      final p = s.pingFor(PingMode.real);
      return p != null && p <= 0 && s.id != selectedServerId;
    }).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'جستجوی سرور یا پروتکل...',
                    filled: true,
                    fillColor: _cardSurface,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => searchQuery = '');
                            },
                          ),
                  ),
                ),
              ),
              if (failedCount > 0) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'حذف $failedCount سرور خطا/تایم‌اوت',
                  icon: const Icon(Icons.auto_delete_outlined, size: 20),
                  onPressed: () {
                    final removed = _removeFailedServers();
                    showSnack('$removed سرور خراب از لیست حذف شد');
                  },
                ),
              ],
            ],
          ),
          if (sortedCodes.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text('همه (${servers.length})',
                          style: const TextStyle(fontSize: 12)),
                      selected: selectedCountryFilter == 'ALL',
                      onSelected: (_) =>
                          setState(() => selectedCountryFilter = 'ALL'),
                    ),
                  ),
                  for (final code in sortedCodes)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(
                          '${flagOf(code)} ${kCountryNames[code] ?? code}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selectedCountryFilter == code,
                        onSelected: (_) => setState(() =>
                            selectedCountryFilter =
                                selectedCountryFilter == code ? 'ALL' : code),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final pending = _pendingTarget;
    final connected = pending == null ? isConnected : false;
    final connecting =
        pending != null || isConnecting || _connState == 'DISCONNECTING';
    final accent =
        connected ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
    final statusTitle = pending == false
        ? 'در حال قطع...'
        : connected
            ? 'متصل'
            : connecting
                ? 'در حال اتصال...'
                : 'آماده اتصال';

    final q = searchQuery.toLowerCase();
    final isFiltering = q.isNotEmpty || selectedCountryFilter != 'ALL';
    final filteredServers = servers.where((s) {
      if (selectedCountryFilter != 'ALL' &&
          s.countryCode.toUpperCase() != selectedCountryFilter) {
        return false;
      }
      if (q.isNotEmpty &&
          !s.remark.toLowerCase().contains(q) &&
          !s.protocol.toLowerCase().contains(q) &&
          !s.subName.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    final grouped = <String, List<ServerItem>>{};
    for (final server in filteredServers) {
      grouped.putIfAbsent(server.subId, () => <ServerItem>[]).add(server);
    }

    final sections = <Widget>[
      if ((grouped['manual'] ?? const <ServerItem>[]).isNotEmpty)
        _groupSection(
          id: 'manual',
          title: 'سرورهای دستی',
          servers: grouped['manual']!,
        ),
      for (final sub in subscriptions)
        if (!isFiltering || (grouped[sub.id] ?? const <ServerItem>[]).isNotEmpty)
          _groupSection(
            id: sub.id,
            title: sub.name,
            sub: sub,
            servers: grouped[sub.id] ?? const <ServerItem>[],
          ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgBottom],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _homeHeader(),
            if (isTestingAll)
              LinearProgressIndicator(
                value: pingTestsTotal == 0
                    ? null
                    : pingTestsCompleted / pingTestsTotal,
                minHeight: 2,
              ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  const SizedBox(height: 6),
                  Center(
                    child: _PowerButton(
                      connected: connected,
                      connecting: connecting,
                      accent: accent,
                      isDark: _isDark,
                      onTap: toggleVpn,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      statusTitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: connected
                            ? const Color(0xFF10B981)
                            : (_isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ),
                  if (hasSleepTimer)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.bedtime_rounded,
                              size: 16, color: Color(0xFF8B5CF6)),
                          label: Text(
                            'قطع خودکار تا ${_fmtDurationClock(_sleepRemaining)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: _showSleepTimerSheet,
                        ),
                      ),
                    ),
                  if (connected) ...[
                    const SizedBox(height: 12),
                    _liveStatsCard(),
                  ],
                  // دکمه Hide everything (آپشن ۱)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _hideEverything = !_hideEverything),
                      child: Text(
                        _hideEverything ? 'نمایش سرورها' : 'مخفی کردن همه',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  if (!_hideEverything) ...[
                    if (availableVersion.isNotEmpty) _updateBanner(),
                    if (servers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: _cardSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_outlined,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text('هنوز سروری اضافه نشده است',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text(
                              'لینک اشتراک یا کانفیگ خود را از کلیپ‌بورد یا دوربین اضافه کنید',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _showAddChooser,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('افزودن سرور یا اشتراک'),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _buildServerFilterBar(),
                      if (sections.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'هیچ سروری با این فیلتر پیدا نشد',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ...sections,
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _pingTone(int? ping) {
    if (ping == null) return Colors.grey;
    if (ping <= 0) return const Color(0xFFFF5252);
    if (ping <= 200) return const Color(0xFF10B981);
    if (ping <= 400) return const Color(0xFFF59E0B);
    return const Color(0xFFFF5252);
  }

  Widget _serverTile(ServerItem server) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _serverTileBody(server),
    );
  }

  Widget _serverTileBody(ServerItem server) {
    final isSelected = server.id == selectedServerId;
    final isFav = _favoriteServerIds.contains(server.id);
    final ping = server.pingFor(PingMode.real);
    final tone = _pingTone(ping);
    final selectedBg = _isDark
        ? Colors.white.withOpacity(0.08)
        : const Color(0xFF4F46E5).withOpacity(0.07);
    final indicatorColor = _isDark ? Colors.white : const Color(0xFF4F46E5);

    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      child: InkWell(
        onLongPress: () => _showServerSheet(server),
        onTap: () async {
          setState(() => selectedServerId = server.id);
          await savePersistentData();
          await reconnectIfNeeded();
        },
        child: Container(
          decoration: BoxDecoration(
            border: isSelected
                ? Border(left: BorderSide(color: indicatorColor, width: 3.5))
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Text(flagOf(server.countryCode),
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.remark,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.protocol.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                ping == null ? '' : (ping <= 0 ? 'خطا' : '$ping ms'),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: tone),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 19,
                  color: isFav ? const Color(0xFFF59E0B) : Colors.grey,
                ),
                onPressed: () => _toggleFavorite(server),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: _isDark ? Colors.white38 : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerSheet(ServerItem server) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  server.remark,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  '${server.protocol} • ${server.subName}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: const Text('نمایش QR Code سرور'),
                onTap: () {
                  Navigator.pop(ctx);
                  final payload = server.rawUrl.isNotEmpty
                      ? server.rawUrl
                      : server.fullJsonConfig;
                  _showQrShareSheet(
                    'QR Code سرور',
                    server.remark,
                    payload,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('مشاهده و ویرایش کانفیگ JSON'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showJsonEditorModal(server);
                },
              ),
              if (server.rawUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('کپی لینک سرور'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: server.rawUrl));
                    Navigator.pop(ctx);
                    showSnack('لینک سرور کپی شد');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('تست پینگ این سرور'),
                onTap: () {
                  Navigator.pop(ctx);
                  pingSingleServer(server);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title:
                    const Text('حذف سرور', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    servers.removeWhere((x) => x.id == server.id);
                    if (selectedServerId == server.id) {
                      selectedServerId =
                          servers.isNotEmpty ? servers.first.id : '';
                    }
                  });
                  savePersistentData();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editPingUrl() {
    final controller = TextEditingController(text: pingTestUrl);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(Icons.link_rounded, const Color(0xFF3B82F6),
                  'آدرس تست پینگ'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: 'https://...'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final v = controller.text.trim();
                        if (v.startsWith('https://') ||
                            v.startsWith('http://')) {
                          _applySetting(() => pingTestUrl = v);
                          savePersistentData();
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('ذخیره'),
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

  void _openAppsPage() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _buildAppsPage(),
    ));
  }

  void _autoPickIranianApps({bool force = false}) {
    if (iranianAutoDone && !force) return;
    var added = 0;
    for (final app in _installedApps) {
      final pkg = app['package']!;
      final matched = isIranianPackage(pkg) || isIranianBankLabel(app['name']!);
      if (matched && bypassApps.add(pkg)) added++;
    }
    iranianAutoDone = true;
    savePersistentData();
    if (mounted) {
      showSnack(added > 0
          ? '$added برنامهٔ ایرانی به‌صورت خودکار خارج از VPN قرار گرفت'
          : 'برنامهٔ ایرانی جدیدی پیدا نشد');
    }
  }

  Future<void> _loadInstalledApps() async {
    try {
      final raw = await kQuickControlsChannel
              .invokeListMethod<dynamic>('getLaunchableApps') ??
          <dynamic>[];
      final apps = <StringMap>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final pkg = (item['package'] ?? '').toString();
        if (pkg.isEmpty) continue;
        apps.add({'name': (item['name'] ?? pkg).toString(), 'package': pkg});
      }
      apps.sort(
          (a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
      _installedApps = apps;
      _autoPickIranianApps();
    } catch (_) {
      showSnack('فهرست برنامه‌ها گرفته نشد');
    }
    _appsLoading = false;
  }

  Widget _buildAppsPage() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          if (_installedApps.isEmpty && !_appsLoading) {
            _appsLoading = true;
            _loadInstalledApps().then((_) {
              if (ctx.mounted) setLocal(() {});
            });
          }
          final q = _appsQuery.toLowerCase();
          final shown = _installedApps
              .where((a) =>
                  q.isEmpty ||
                  a['name']!.toLowerCase().contains(q) ||
                  a['package']!.contains(q))
              .toList();

          return Scaffold(
            appBar: AppBar(
              title: const Text('برنامه‌های خارج از VPN'),
              actions: [
                TextButton(
                  onPressed: () {
                    _autoPickIranianApps(force: true);
                    setLocal(() {});
                  },
                  child: const Text('ایرانی‌ها'),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    onChanged: (v) {
                      _appsQuery = v;
                      setLocal(() {});
                    },
                    decoration: const InputDecoration(
                      hintText: 'جستجوی برنامه',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'برنامه‌های انتخاب‌شده مستقیم و بدون VPN وصل می‌شوند.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
                  ),
                ),
                Expanded(
                  child: _appsLoading && _installedApps.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final app = shown[i];
                            final pkg = app['package']!;
                            return CheckboxListTile(
                              value: bypassApps.contains(pkg),
                              title: Text(app['name']!),
                              subtitle: Text(pkg,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(fontSize: 11)),
                              onChanged: (v) {
                                _applySetting(() {
                                  if (v == true) {
                                    bypassApps.add(pkg);
                                  } else {
                                    bypassApps.remove(pkg);
                                  }
                                });
                                setLocal(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _exportBackup() {
    final data = {
      'app': 'SHIN',
      'version': kAppVersion,
      'servers': servers.map((e) => e.toJson()).toList(),
      'subscriptions': subscriptions.map((e) => e.toJson()).toList(),
      'dns': selectedDns,
      'bypassIran': bypassIran,
      'bypassLan': bypassLan,
      'customDirectIps': customDirectIps,
      'customDirectDomains': customDirectDomains,
      'customRoutingName': customRoutingName,
      'enableMux': enableMux,
      'enableTlsFragment': enableTlsFragment,
      'enableAdBlock': enableAdBlock,
      'autoFailover': connectionHealthMonitor,
      'enableIPv6': enableIPv6,
      'mtuSize': mtuSize,
    };
    final jsonStr = jsonEncode(data);
    Clipboard.setData(ClipboardData(text: jsonStr));
    showSnack('پشتیبان کامل در کلیپ‌بورد کپی شد 📋');
  }

  Future<void> _importBackup() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = d?.text?.trim() ?? '';
    if (raw.isEmpty) {
      showSnack('کلیپ‌بورد خالی است!');
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['app'] == 'SHIN') {
        final serverList = decoded['servers'];
        if (serverList is List) {
          for (final s in serverList) {
            try {
              servers.add(ServerItem.fromJson(JsonMap.from(s)));
            } catch (_) {}
          }
        }
        final subList = decoded['subscriptions'];
        if (subList is List) {
          for (final s in subList) {
            try {
              subscriptions.add(SubscriptionItem.fromJson(JsonMap.from(s)));
            } catch (_) {}
          }
        }
        if (decoded['customDirectIps'] is List) {
          customDirectIps = List<String>.from(decoded['customDirectIps']);
        }
        if (decoded['customDirectDomains'] is List) {
          customDirectDomains =
              List<String>.from(decoded['customDirectDomains']);
        }
        if (decoded['customRoutingName'] is String) {
          customRoutingName = decoded['customRoutingName'];
        }
        await savePersistentData();
        setState(() {});
        showSnack('پشتیبان با موفقیت بازیابی شد ✅');
      } else {
        showSnack('فرمت فایل پشتیبان معتبر نیست');
      }
    } catch (_) {
      showSnack('خطا در خواندن فایل پشتیبان');
    }
  }

  Widget _buildAdvancedSettingsPage(void Function(void Function()) setLocal) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات فوق پیشرفته')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle('ضد فیلترینگ و پایداری اتصال'),
          _settingsCard([
            _settingsSwitch(
              icon: Icons.auto_fix_high_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'دور زدن محدودیت اپراتورها (TLS Fragment)',
              subtitle: 'تکه‌تکه کردن پکت‌های TLS برای همراه اول و ایرانسل',
              value: enableTlsFragment,
              onChanged: (v) async {
                _applySetting(() => enableTlsFragment = v);
                setLocal(() {});
                await savePersistentData();
                await reconnectIfNeeded();
              },
            ),
            if (enableTlsFragment)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.segment_rounded,
                      color: Color(0xFF10B981), size: 20),
                ),
                title: const Text('الگوی Fragment',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'tlshello', label: Text('TLS Hello')),
                    ButtonSegment(value: '1-3', label: Text('قوی (1-3)')),
                  ],
                  selected: {fragmentPackets},
                  onSelectionChanged: (v) async {
                    _applySetting(() {
                      fragmentPackets = v.first;
                      if (v.first == '1-3') {
                        fragmentLength = '5-10';
                        fragmentInterval = '5-10';
                      } else {
                        fragmentLength = '10-20';
                        fragmentInterval = '10-20';
                      }
                    });
                    setLocal(() {});
                    await savePersistentData();
                    await reconnectIfNeeded();
                  },
                ),
              ),
            _settingsSwitch(
              icon: Icons.swap_horiz_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'پایش سلامت اتصال',
              subtitle:
                  'تشخیص افت کیفیت و پیشنهاد سرور جایگزین؛ تغییر سرور فقط با تأیید شما',
              value: connectionHealthMonitor,
              onChanged: (v) {
                _applySetting(() => connectionHealthMonitor = v);
                setLocal(() {});
                if (v && isConnected) {
                  _startFailoverWatchdog();
                } else {
                  _stopFailoverWatchdog();
                }
              },
            ),
          ]),
          _sectionTitle('تنظیمات هسته Xray'),
          _settingsCard([
            _settingsSwitch(
              icon: Icons.alt_route_rounded,
              iconColor: const Color(0xFF6366F1),
              title: 'تجمیع اتصال (Mux)',
              subtitle:
                  'ارسال چند درخواست روی یک اتصال (برای Reality خاموش باشد)',
              value: enableMux,
              onChanged: (v) {
                _applySetting(() => enableMux = v);
                setLocal(() {});
              },
            ),
            _settingsSwitch(
              icon: Icons.shield_outlined,
              iconColor: const Color(0xFFEF4444),
              title: 'پذیرش TLS نامعتبر',
              subtitle: 'گواهی‌های ناامن یا خودامضا را بپذیر',
              value: allowInsecureDefault,
              onChanged: (v) {
                _applySetting(() => allowInsecureDefault = v);
                setLocal(() {});
              },
            ),
            _settingsSwitch(
              icon: Icons.language_rounded,
              iconColor: const Color(0xFF06B6D4),
              title: 'پشتیبانی از IPv6',
              subtitle: 'فقط در صورت پشتیبانی اپراتور یا اینترنت شما',
              value: enableIPv6,
              onChanged: (v) {
                _applySetting(() => enableIPv6 = v);
                setLocal(() {});
              },
            ),
            _settingsSwitch(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'بیدار نگه‌داشتن پردازنده (Keep CPU Awake)',
              subtitle: 'جلوگیری از قطع و فریز شدن VPN هنگام خاموشی صفحه',
              value: keepCpuAlive,
              onChanged: (v) {
                _applySetting(() => keepCpuAlive = v);
                setLocal(() {});
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: Color(0xFF8B5CF6), size: 20),
              ),
              title: const Text('اندازه MTU پکت‌ها',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: DropdownButton<int>(
                value: mtuSize,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 1280, child: Text('1280 (پایدار)')),
                  DropdownMenuItem(value: 1400, child: Text('1400 (همراه)')),
                  DropdownMenuItem(
                      value: 1500, child: Text('1500 (استاندارد)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _applySetting(() => mtuSize = val);
                    setLocal(() {});
                  }
                },
              ),
            ),
          ]),
          _sectionTitle('تنظیمات و متد تست پینگ'),
          _settingsCard([
            _settingsSwitch(
              icon: Icons.timeline_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'اعمال مسیریابی روی پینگ',
              subtitle: 'قوانین بای‌پس ایران و LAN را در پینگ محاسبه کن',
              value: pingBypassRouting,
              onChanged: (v) {
                _applySetting(() => pingBypassRouting = v);
                setLocal(() {});
              },
            ),
            _settingsSwitch(
              icon: Icons.filter_2_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'بهترین از دو پینگ (Best of Two)',
              subtitle: 'دو پینگ مجزا ارسال و نتیجه سریع‌تر ثبت می‌شود',
              value: pingBestOfTwo,
              onChanged: (v) {
                _applySetting(() => pingBestOfTwo = v);
                setLocal(() {});
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timer_outlined,
                    color: Color(0xFFEC4899), size: 20),
              ),
              title: const Text('مهلت پینگ (Timeout)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5s')),
                  ButtonSegment(value: 10, label: Text('10s')),
                  ButtonSegment(value: 15, label: Text('15s')),
                ],
                selected: {pingProxyTimeoutSec},
                onSelectionChanged: (v) {
                  _applySetting(() => pingProxyTimeoutSec = v.first);
                  setLocal(() {});
                  savePersistentData();
                },
              ),
            ),
            _settingsTile(
              icon: Icons.link_rounded,
              iconColor: const Color(0xFF64748B),
              title: 'آدرس تست تأخیر (Ping URL)',
              subtitle: pingTestUrl,
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: _editPingUrl,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    final hasCustomRouting =
        customDirectIps.isNotEmpty || customDirectDomains.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _sectionTitle('پوسته و ظاهر'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: SegmentedButton<AppThemeModeSetting>(
              segments: const [
                ButtonSegment(
                  value: AppThemeModeSetting.system,
                  label: Text('سیستم'),
                  icon: Icon(Icons.brightness_auto_rounded),
                ),
                ButtonSegment(
                  value: AppThemeModeSetting.dark,
                  label: Text('تیره'),
                  icon: Icon(Icons.dark_mode_rounded),
                ),
                ButtonSegment(
                  value: AppThemeModeSetting.light,
                  label: Text('روشن'),
                  icon: Icon(Icons.light_mode_rounded),
                ),
              ],
              selected: {widget.currentTheme},
              onSelectionChanged: (val) {
                widget.onThemeChanged(val.first);
                _settingsRebuild?.call();
              },
            ),
          ),
          _sectionTitle('مسیریابی هوشمند و ترافیک'),
          _settingsCard([
            _settingsTile(
              icon: Icons.apps_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'برنامه‌های خارج از VPN (Split Tunneling)',
              subtitle: '${bypassApps.length} برنامه مستقیم وصل می‌شوند',
              onTap: _openAppsPage,
            ),
            _settingsSwitch(
              icon: Icons.flag_circle_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'بای‌پس ایران',
              subtitle: 'دامنه‌های .ir و رنج‌های روتینگ ایران مستقیم باز شوند',
              value: bypassIran,
              onChanged: (v) => _applySetting(() => bypassIran = v),
            ),
            _settingsTile(
              icon: Icons.alt_route_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'قوانین روتینگ سفارشی (Happ / لیست IP)',
              subtitle: hasCustomRouting
                  ? '${customDirectIps.length} رنج IP • ${customDirectDomains.length} دامنه'
                  : 'چسباندن متن happ://routing/add/... یا لیست IP',
              onTap: _showCustomRoutingSheet,
            ),
            _settingsSwitch(
              icon: Icons.block_rounded,
              iconColor: const Color(0xFFEF4444),
              title: 'مسدودساز تبلیغات و ردیاب‌ها (AdBlock)',
              subtitle:
                  'حذف تبلیغات درون‌برنامه‌ای و سایت‌ها با هسته Xray و AdGuard',
              value: enableAdBlock,
              onChanged: (v) async {
                _applySetting(() => enableAdBlock = v);
                await savePersistentData();
                await reconnectIfNeeded();
              },
            ),
            _settingsSwitch(
              icon: Icons.power_settings_new_rounded,
              iconColor: const Color(0xFF14B8A6),
              title: 'اتصال خودکار پس از روشن شدن گوشی',
              subtitle: 'برقراری اتصال VPN بلافاصله بعد از ری‌استارت دستگاه',
              value: autoConnectOnBoot,
              onChanged: (v) => _applySetting(() => autoConnectOnBoot = v),
            ),
            _settingsSwitch(
              icon: Icons.router_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'بای‌پس شبکهٔ محلی (LAN)',
              subtitle: 'ارتباط مستقیم با مودم و دستگاه‌های داخل خانه',
              value: bypassLan,
              onChanged: (v) => _applySetting(() => bypassLan = v),
            ),
          ]),
          _sectionTitle('سرور DNS ترجیحی'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in kDnsOptions)
                  ChoiceChip(
                    label: Text(
                      d == '94.140.14.14'
                          ? 'AdGuard DNS'
                          : d == '1.1.1.1'
                              ? 'Cloudflare (1.1.1.1)'
                              : d == '8.8.8.8'
                                  ? 'Google (8.8.8.8)'
                                  : d,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selectedDns == d,
                    onSelected: (_) {
                      _applySetting(() => selectedDns = d);
                      savePersistentData();
                    },
                  ),
              ],
            ),
          ),
          _sectionTitle('تنظیمات اختصاصی'),
          _settingsCard([
            _settingsTile(
              icon: Icons.tune_rounded,
              iconColor: const Color(0xFF6366F1),
              title: 'تنظیمات فوق پیشرفته موتور',
              subtitle: 'TLS Fragment، Auto-Failover، MTU و Mux',
              onTap: _openAdvancedSettings,
            ),
            _settingsTile(
              icon: Icons.file_upload_outlined,
              iconColor: const Color(0xFF0EA5E9),
              title: 'پشتیبان‌گیری از اطلاعات (Export)',
              subtitle: 'کپی کردن تمام سرورها و کانفیگ‌ها در کلیپ‌بورد',
              onTap: _exportBackup,
            ),
            _settingsTile(
              icon: Icons.file_download_outlined,
              iconColor: const Color(0xFF10B981),
              title: 'بازیابی اطلاعات (Import Backup)',
              subtitle: 'بازگردانی اطلاعات از متن کپی‌شده',
              onTap: _importBackup,
            ),
          ]),
          _sectionTitle('اطلاعات و پشتیبانی'),
          _settingsCard([
            _settingsTile(
              icon: Icons.system_update_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'بررسی بروزرسانی برنامه',
              subtitle: 'نسخهٔ فعال: $kAppVersion',
              trailing: isCheckingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => checkForAppUpdate(),
            ),
            _settingsTile(
              icon: Icons.memory_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'هستهٔ پردازشی Xray',
              subtitle: coreVersion,
              trailing: const Icon(Icons.sync_rounded, size: 20),
              onTap: checkForXrayCoreUpdate,
            ),
            _settingsTile(
              icon: Icons.fingerprint_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'شناسه اختصاصی دستگاه (HWID)',
              subtitle: hwid,
              trailing: const Icon(Icons.copy_rounded, size: 18),
              onTap: () {
                Clipboard.setData(ClipboardData(text: hwid));
                showSnack('شناسه HWID کپی شد');
              },
            ),
          ]),
          _sectionTitle('منطقهٔ پاکسازی'),
          _settingsCard([
            _settingsTile(
              icon: Icons.delete_sweep_rounded,
              iconColor: const Color(0xFFEF4444),
              title: 'حذف همه سرورها و بازنشانی کامل',
              subtitle: 'حذف تمامی سرورها، اشتراک‌ها و ریست به حالت اول',
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('پاکسازی کامل داده‌ها'),
                    content: const Text(
                        'آیا مطمئن هستید؟ همه سرورها و تنظیمات حذف خواهند شد.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('انصراف')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حذف همه'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  if (isConnected || isConnecting) {
                    await _stopVpn();
                  }
                  setState(() {
                    servers.clear();
                    subscriptions.clear();
                    customDirectIps.clear();
                    customDirectDomains.clear();
                    customRoutingName = '';
                    selectedServerId = '';
                    selectedGroupFilter = 'ALL';
                    selectedCountryFilter = 'ALL';
                  });
                  await savePersistentData();
                  showSnack('تمام سرورها و داده‌ها پاکسازی شدند');
                }
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _PowerButton({
    required this.connected,
    required this.connecting,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final outerCircle =
        isDark ? const Color(0xFF2E2C8A) : const Color(0xFFE0E7FF);
    final innerCircle = isDark ? const Color(0xFF212066) : Colors.white;
    final powerIconColor = connected
        ? const Color(0xFF10B981)
        : (isDark ? const Color(0xFF0D0F2E) : const Color(0xFF4338CA));

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 210,
        height: 210,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 204,
              height: 204,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: connected
                      ? const [
                          Color(0xFF10B981),
                          Color(0xFF34D399),
                          Color(0xFF059669),
                          Color(0xFF10B981)
                        ]
                      : const [
                          Color(0xFF3B82F6),
                          Color(0xFF8B5CF6),
                          Color(0xFFEC4899),
                          Color(0xFF3B82F6)
                        ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.2),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? const Color(0xFF111642)
                        : const Color(0xFFF4F5F8),
                  ),
                ),
              ),
            ),
            if (connecting)
              SizedBox(
                width: 204,
                height: 204,
                child: CircularProgressIndicator(strokeWidth: 3, color: accent),
              ),
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: outerCircle,
                boxShadow: [
                  BoxShadow(
                    color: (connected
                            ? const Color(0xFF10B981)
                            : const Color(0xFF4F46E5))
                        .withOpacity(isDark ? 0.35 : 0.15),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 126,
                  height: 126,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: innerCircle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 56,
                      color: powerIconColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedGraphPainter extends CustomPainter {
  final List<double> dl;
  final List<double> ul;

  _SpeedGraphPainter({required this.dl, required this.ul});

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = [
      ...dl,
      ...ul,
      1024.0,
    ].reduce((a, b) => a > b ? a : b);

    void drawSeries(List<double> data, Color color) {
      if (data.length < 2) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      final path = Path();
      final stepX = size.width / (data.length - 1);
      for (var i = 0; i < data.length; i++) {
        final x = i * stepX;
        final y = size.height -
            (data[i] / maxVal).clamp(0.0, 1.0) * (size.height - 4) -
            2;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawSeries(dl, const Color(0xFF22C55E));
    drawSeries(ul, const Color(0xFFA855F7));
  }

  @override
  bool shouldRepaint(covariant _SpeedGraphPainter oldDelegate) => true;
}
