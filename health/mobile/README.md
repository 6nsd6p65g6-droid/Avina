# أفينا على الهاتف (Android وiPhone)

غلاف [Capacitor](https://capacitorjs.com) حول تطبيق الويب في `../index.html`. الكود واحد، والنسخة تُحدَّد بقناة التوزيع:

| القناة | الأمر | الدفع داخل التطبيق |
|---|---|---|
| `play` (Google Play) | `npm run sync:android:play` | لا (قواعد Google) |
| `appstore` (App Store) | `npm run sync:ios` | لا (قواعد Apple) |
| `direct` (APK من موقعك) | `npm run sync:android:direct` | كل الطرق حسب البلد |

## البناء
- **أندرويد:** `scripts/build-android.sh`. يُخرج إلى `dist/`:
  - `avina-<v>-play.aab`.
  - `avina-<v>-direct.apk`.
  - يحتاج Java 21 وAndroid SDK وملف `android/keystore.properties`. الملف خارج Git، وفيه:
    ```
    storeFile=/مسار/avina-upload.jks
    storePassword=…
    keyAlias=avina-upload
    keyPassword=…
    ```
- **iPhone:** يلزم Mac عليه Xcode (`npx cap open ios`)، أو Codemagic عبر `ci/codemagic.yaml`.
- **الأيقونات وشاشة البدء:**
  - مصدرها مجلد `assets/`.
  - أعد توليدها بالأمر `npm run assets`.
  - لتغيير الشعار شغّل سكربت الأيقونات ثم الأمر أعلاه.

بعد أي تعديل على `../index.html` أعد تشغيل أمر المزامنة للقناة المطلوبة قبل البناء.
