#!/usr/bin/env bash
# يبني نسختي أندرويد في مجلد dist/:
#   avina-<v>-play.aab   لمتجر Google Play (بدون دفع خارجي، كما تشترط Google)
#   avina-<v>-direct.apk للتنزيل المباشر من موقعك (كل طرق الدفع)
# يحتاج: Java 21 وAndroid SDK (ANDROID_HOME) وملف android/keystore.properties لتوقيع الإصدار.
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
V=$(node -p "require('./package.json').version")
mkdir -p dist
[ -f android/keystore.properties ] || echo "تنبيه: لا يوجد android/keystore.properties، سيُبنى الإصدار غير موقّع."

AVINA_CHANNEL=play node scripts/copy-web.mjs && npx cap sync android >/dev/null
(cd android && ./gradlew --no-daemon -q --max-workers=1 bundleRelease)
cp android/app/build/outputs/bundle/release/app-release.aab "dist/avina-$V-play.aab"

AVINA_CHANNEL=direct node scripts/copy-web.mjs && npx cap sync android >/dev/null
(cd android && ./gradlew --no-daemon -q --max-workers=1 assembleRelease)
cp android/app/build/outputs/apk/release/app-release*.apk "dist/avina-$V-direct.apk"
ls -la dist
