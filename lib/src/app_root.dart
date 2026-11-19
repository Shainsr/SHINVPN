part of '../main.dart';

class ShinVPNApp extends StatefulWidget {
  const ShinVPNApp({super.key});

  @override
  State<ShinVPNApp> createState() => _ShinVPNAppState();
}

/// سطح اندازه ظاهر: ۰ کوچک، ۱ متوسط (پیش‌فرض)، ۲ بزرگ
final ValueNotifier<int> kUiSizeLevel = ValueNotifier<int>(1);
const List<double> kUiScaleFactors = [0.68, 0.78, 0.88];

Future<void> setUiSizeLevel(int level) async {
  kUiSizeLevel.value = level.clamp(0, kUiScaleFactors.length - 1);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('ui_size_level', kUiSizeLevel.value);
}

class _ShinVPNAppState extends State<ShinVPNApp> {
  AppThemeModeSetting currentTheme = AppThemeModeSetting.system;

  @override
  void initState() {
    super.initState();
    loadSavedTheme();
  }

  Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('saved_theme_mode_v2') ?? 0;
    kUiSizeLevel.value =
        (prefs.getInt('ui_size_level') ?? 1).clamp(0, kUiScaleFactors.length - 1);
    if (!mounted) return;
    setState(() {
      currentTheme = AppThemeModeSetting.values[
          idx.clamp(0, AppThemeModeSetting.values.length - 1)];
    });
  }

  Future<void> setTheme(AppThemeModeSetting mode) async {
    setState(() => currentTheme = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('saved_theme_mode_v2', mode.index);
  }

  ThemeMode get _themeMode {
    switch (currentTheme) {
      case AppThemeModeSetting.system:
        return ThemeMode.system;
      case AppThemeModeSetting.dark:
        return ThemeMode.dark;
      case AppThemeModeSetting.light:
        return ThemeMode.light;
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0E17) : const Color(0xFFF3F6FB);
    final card = isDark ? const Color(0xFF131926) : const Color(0xFFFFFFFF);
    final text = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    const accent = Color(0xFF3B82F6);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor:
          isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
      colorScheme: isDark
          ? ColorScheme.dark(primary: accent, secondary: accent, surface: card)
          : ColorScheme.light(primary: accent, secondary: accent, surface: card),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
          fontFamily: 'Vazirmatn', bodyColor: text, displayColor: text),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Vazirmatn'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SHIN',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) => ValueListenableBuilder<int>(
        valueListenable: kUiSizeLevel,
        builder: (context, level, _) {
          final f = kUiScaleFactors[level];
          if (f == 1.0 || child == null) return child ?? const SizedBox();
          // کوچک‌کردن کل رابط: صفحه با اندازه بزرگ‌تر رندر و با ضریب f کوچک می‌شود
          final mq = MediaQuery.of(context);
          final size = mq.size;
          return MediaQuery(
            data: mq.copyWith(size: size / f),
            child: Transform.scale(
              scale: f,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width / f,
                height: size.height / f,
                child: child,
              ),
            ),
          );
        },
      ),
      home: MainShell(onThemeChanged: setTheme, currentTheme: currentTheme),
    );
  }
}

