# SHIN VPN

کلاینت VPN اندروید با Flutter و هستهٔ Xray.

## پیش‌نیازها

- Flutter stable (نسخهٔ CI: `3.29.3`)
- JDK 17
- Android SDK با Build Tools سازگار

## دریافت وابستگی‌ها و اجرا

```bash
flutter pub get
flutter run
```

## ساخت APK

```bash
flutter build apk --release --split-per-abi
```

برای ساخت Release محلی، فایل `android/key.properties` و keystore معتبر لازم است. این فایل‌ها نباید وارد Git شوند.

### ساخت کلید امضای انتشار

```bash
keytool -genkey -v -keystore shin-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias shin
```

مقادیر `key.properties` باید شامل `storePassword`، `keyPassword`، `keyAlias` و `storeFile` باشند. از keystore نسخهٔ پشتیبان امن نگه دارید؛ تغییر کلید امضا مانع نصب آپدیت روی نسخهٔ قبلی می‌شود.

## GitHub Actions و انتشار

Workflow در `.github/workflows/android.yml` اجرا می‌شود:

- روی branch و Pull Request از کلید موقت CI استفاده می‌کند.
- روی tag با الگوی `v*` فقط از کلید انتشار ذخیره‌شده در GitHub Secrets استفاده می‌کند.
- برای انتشار tag، این Secrets لازم‌اند: `KEYSTORE_BASE64`، `KEYSTORE_PASSWORD`، `KEY_ALIAS` و `KEY_PASSWORD`.
- APKهای `armeabi-v7a` و `arm64-v8a` ساخته می‌شوند.

برای انتشار نسخهٔ جدید:

1. مقدار `version` در `pubspec.yaml` و مقدار پیش‌فرض `kAppVersion` در `lib/src/app_support.dart` را هماهنگ کنید.
2. شمارهٔ build بعد از `+` در `pubspec.yaml` را افزایش دهید.
3. تغییرات را push کنید و tag بسازید:

```bash
git tag v1.00.7
git push origin v1.00.7
```

## ساختار پروژه

```text
.
├── .github/workflows/       # فرایند CI و انتشار APK
├── android/                 # تنظیمات Gradle، Manifest، منابع و کد Native Android
├── assets/fonts/            # فونت‌های Vazirmatn
├── docs/                    # مستندات و گزارش بررسی پروژه
├── lib/
│   ├── main.dart            # importها، partها و نقطهٔ ورود برنامه
│   └── src/
│       ├── app_support.dart # ثابت‌ها، ابزارها، بروزرسانی و کارهای پس‌زمینه
│       ├── config_parser.dart # تجزیه لینک‌ها، کانفیگ و قوانین روتینگ
│       ├── server_models.dart # مدل سرورها، اشتراک‌ها و دریافت اشتراک
│       ├── app_root.dart    # پوسته و تنظیمات اصلی Flutter
│       ├── main_shell.dart  # صفحه و منطق اصلی برنامه
│       └── onboarding.dart  # راه‌اندازی اولیه
├── pubspec.yaml
└── README.md
```

فایل‌های `src` با Dart `part` به یک library مشترک تعلق دارند؛ بنابراین جابه‌جایی کدها بدون تغییر دسترسی اعضای خصوصی و رفتار فعلی انجام شده است.
