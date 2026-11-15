part of '../main.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringMap = Map<String, String>;
typedef IntMap = Map<String, int>;

const MethodChannel kQuickControlsChannel =
    MethodChannel('com.example.happ_vpn/quick_controls');

enum PingMode { real }

extension PingModeLabel on PingMode {
  String get label => 'پینگ واقعی';
}

const String kDefaultPingUrl = 'https://www.gstatic.com/generate_204';

class ServerEndpoint {
  final String host;
  final int port;
  const ServerEndpoint(this.host, this.port);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const ShinVPNApp());
}

// ---------------------------------------------------------------------------
// توابع بروزرسانی و ابزارهای کمکی
// ---------------------------------------------------------------------------

bool isNewerVersion(String remote, String local) {
  List<int> parts(String v) => v
      .replaceAll(RegExp(r'[^0-9.]'), '')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  final a = parts(remote);
  final b = parts(local);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

Future<StringMap?> fetchLatestReleaseInfo() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'),
    );
    req.headers.set('User-Agent', 'SHIN-Updater');
    req.headers.set('Accept', 'application/vnd.github+json');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(resp).join();
    final data = jsonDecode(body);
    if (data is! Map) return null;

    final tag =
        (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), '');
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
    return {
      'tag': tag,
      'notes': (data['body'] ?? '').toString(),
      'apk': apk,
    };
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

class UpdateNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification_vpn'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showNewVersion(String version) async {
    await _plugin.show(
      7001,
      'نسخهٔ جدید SHIN ($version)',
      'برای دانلود و نصب، برنامه را باز کنید.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'shin_updates',
          'بروزرسانی برنامه',
          channelDescription: 'اطلاع از نسخهٔ جدید SHIN',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

Future<void> runBackgroundUpdateCheck() async {
  final info = await fetchLatestReleaseInfo();
  if (info == null) return;
  final tag = info['tag'] ?? '';
  if (tag.isEmpty || !isNewerVersion(tag, kAppVersion)) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('notified_update_tag') == tag) return;

  await UpdateNotifier.init();
  await UpdateNotifier.showNewVersion(tag);
  await prefs.setString('notified_update_tag', tag);
}

@pragma('vm:entry-point')
void shinUpdateDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await runBackgroundUpdateCheck();
    } catch (_) {}
    return true;
  });
}

const Set<String> kIranianPackages = {
  'ir.nasim',
  'ir.divar',
  'com.bama.consumer',
  'com.farsitel.bazaar',
  'com.bazambazi',
  'com.samanpr.blu',
  'daal.co',
  'com.bmelat.mobile',
  'com.aparat',
  'cab.snapp.passenger.play',
};

const List<String> kIranianBankWords = [
  'بانک', 'بام', 'سکه', 'ویپاد', 'وپاد', 'فراز', 'همراه بانک', 'ملی', 'ملت',
  'سپه', 'صادرات', 'تجارت', 'پاسارگاد', 'ایران زمین', 'دی جت', 'بلو',
  'همراه کارت', 'آپ', 'قبضینو', 'بانکینو', 'شهر', 'کشاورزی',
  'مسکن', 'توسعه', 'رفاه', 'اقتصاد نوین', 'پست بانک', 'سامان', 'سینا',
  'آینده', 'کارآفرین', 'گردشگری', 'خاورمیانه', 'دی', 'ایران',
  'bank', 'Bank',
];

bool isIranianBankLabel(String name) {
  final n = name.toLowerCase();
  return kIranianBankWords.any((w) => n.contains(w.toLowerCase()));
}

bool isIranianPackage(String pkg) {
  final p = pkg.toLowerCase();
  return p.startsWith('ir.') ||
      p.startsWith('cab.snapp.') ||
      kIranianPackages.contains(p);
}

const Map<String, String> kCountryNames = {
  'DE': 'آلمان', 'US': 'آمریکا', 'GB': 'انگلیس', 'FI': 'فنلاند',
  'NL': 'هلند', 'TR': 'ترکیه', 'FR': 'فرانسه', 'CA': 'کانادا',
  'JP': 'ژاپن', 'SG': 'سنگاپور', 'AE': 'امارات', 'IR': 'ایران',
  'RU': 'روسیه', 'SE': 'سوئد', 'CH': 'سوئیس', 'HK': 'هنگ‌کنگ',
  'AU': 'استرالیا', 'NO': 'نروژ', 'IT': 'ایتالیا', 'ES': 'اسپانیا',
  'KR': 'کره جنوبی', 'IN': 'هند', 'AT': 'اتریش', 'PL': 'لهستان',
  'CZ': 'چک', 'RO': 'رومانی', 'UA': 'اوکراین', 'BG': 'بلغارستان',
  'MD': 'مولداوی', 'AL': 'آلبانی', 'BR': 'برزیل', 'ID': 'اندونزی',
};

const Map<String, List<String>> kCountryKeywords = {
  'DE': ['germany', 'german', 'آلمان', 'frankfurt', 'berlin'],
  'US': ['usa', 'united states', 'america', 'آمریکا', 'new york', 'los angeles'],
  'GB': ['united kingdom', 'england', 'london', 'انگلیس', 'بریتانیا'],
  'FI': ['finland', 'فنلاند', 'helsinki'],
  'NL': ['netherlands', 'holland', 'هلند', 'amsterdam'],
  'TR': ['turkey', 'turkiye', 'ترکیه', 'istanbul'],
  'FR': ['france', 'فرانسه', 'paris'],
  'CA': ['canada', 'کانادا'],
  'JP': ['japan', 'ژاپن', 'tokyo'],
  'SG': ['singapore', 'سنگاپور'],
  'AE': ['uae', 'emirates', 'امارات', 'dubai'],
  'IR': ['iran', 'ایران', 'tehran', 'تهران'],
  'RU': ['russia', 'روسیه', 'moscow'],
  'SE': ['sweden', 'سوئد'],
  'CH': ['switzerland', 'سوئیس'],
  'HK': ['hong kong', 'هنگ'],
  'AU': ['australia', 'استرالیا'],
  'NO': ['norway', 'نروژ'],
  'IT': ['italy', 'ایتالیا'],
  'ES': ['spain', 'اسپانیا'],
  'KR': ['korea', 'کره'],
  'IN': ['india', 'هند'],
  'AT': ['austria', 'اتریش'],
  'PL': ['poland', 'لهستان'],
  'UA': ['ukraine', 'اوکراین'],
};

String detectCountryFromText(String text) {
  final runes = text.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i];
    final b = runes[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      return String.fromCharCodes([a - 0x1F1E6 + 0x41, b - 0x1F1E6 + 0x41]);
    }
  }
  final lower = text.toLowerCase();
  for (final entry in kCountryKeywords.entries) {
    for (final kw in entry.value) {
      if (lower.contains(kw)) return entry.key;
    }
  }
  return '';
}

// ---------------------------------------------------------------------------
// نقاط ورود اجرای بی‌صدا در پس‌زمینه (نوتیفیکیشن، ویجت و Quick Settings)
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> vpnBackgroundDisconnect() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final v2ray = V2ray(
    onStatusChanged: (status) async {
      final connected = status.state == 'CONNECTED';
      await prefs.setBool('bg_vpn_connected', connected);
      try {
        await kQuickControlsChannel.invokeMethod('setConnectionState', {
          'connected': connected,
          'status': status.state,
        });
      } catch (_) {}
    },
  );

  try {
    await v2ray.initialize(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_notification_vpn',
    );
    await prefs.setBool('bg_vpn_connected', false);
    try {
      await kQuickControlsChannel.invokeMethod('setConnectionState', {
        'connected': false,
        'status': 'DISCONNECTED',
      });
    } catch (_) {}
    await v2ray.stopV2Ray();
    await Future.delayed(const Duration(milliseconds: 250));
  } catch (_) {}

  try {
    await kQuickControlsChannel.invokeMethod('backgroundTaskDone');
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> vpnBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isConnected = prefs.getBool('bg_vpn_connected') ?? false;
  final config = prefs.getString('native_ready_config') ?? '';
  final remark = prefs.getString('native_ready_remark') ?? 'SHIN Server';
  const isProxyOnly = false;

  final v2ray = V2ray(
    onStatusChanged: (status) async {
      final connected = status.state == 'CONNECTED';
      await prefs.setBool('bg_vpn_connected', connected);
      try {
        await kQuickControlsChannel.invokeMethod('setConnectionState', {
          'connected': connected,
          'status': status.state,
        });
      } catch (_) {}
    },
  );

  try {
    await v2ray.initialize(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_notification_vpn',
    );
    if (isConnected) {
      await prefs.setBool('bg_vpn_connected', false);
      try {
        await kQuickControlsChannel.invokeMethod('setConnectionState', {
          'connected': false,
          'status': 'DISCONNECTED',
        });
      } catch (_) {}
      await v2ray.stopV2Ray();
      await Future.delayed(const Duration(milliseconds: 250));
    } else if (config.isNotEmpty) {
      if (await v2ray.requestPermission()) {
        await v2ray.startV2Ray(
          remark: remark,
          config: config,
          proxyOnly: isProxyOnly,
          blockedApps:
              ((prefs.getStringList('bypassApps') ?? const <String>[]).isEmpty
                  ? null
                  : prefs.getStringList('bypassApps')),
          bypassSubnets: null,
        );
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
  } catch (_) {}

  try {
    await kQuickControlsChannel.invokeMethod('backgroundTaskDone');
  } catch (_) {}
}

const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0');

const String kUpdateRepo = 'Shainsr/happvpn';

const List<String> kUserAgents = [
  'SHIN/1.1.0 (Android; Xray/26.10.31)',
  'v2rayNG/1.9.12',
  'SHIN/1.1.0 (Android)',
];

const List<String> kDnsOptions = [
  '1.1.1.1',
  '8.8.8.8',
  '9.9.9.9',
  '94.140.14.14',
  '208.67.222.222',
];

const List<String> kSupportedSchemes = [
  'vless',
  'vmess',
  'trojan',
  'ss',
  'socks',
  'socks5',
];

enum AppThemeModeSetting { system, dark, light }

