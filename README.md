# پروکسی‌یاب

برنامهٔ Flutter برای دریافت و بررسی فهرست پراکسی‌های عمومی تلگرام. برنامه امکان مرتب‌کردن پراکسی‌ها بر اساس پاسخ‌گویی، ذخیرهٔ موارد دلخواه و بازکردن یا کپی‌کردن لینک پراکسی را فراهم می‌کند. نسخهٔ وب هم برای مرورگرهای موبایل در پوشهٔ `web` آماده است.

## اجرا

```sh
flutter pub get
flutter run
```

## ساخت APK اندروید

```sh
flutter build apk --release
```

خروجی در `build/app/outputs/flutter-apk/app-release.apk` قرار می‌گیرد. تنظیم فعلی Gradle از کلید debug برای امضای APK استفاده می‌کند؛ برای انتشار در فروشگاه‌ها باید کلید امضای release اختصاصی تنظیم و نگهداری شود.

## نسخه

نسخهٔ فعلی: `1.0.1+2`

## دانلود آخرین نسخهٔ اندروید

[دانلود APK](https://github.com/balakhial/proxy_finder/releases/latest/download/proxy-finder.apk)
