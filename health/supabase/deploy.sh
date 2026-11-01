#!/usr/bin/env bash
# إعداد Supabase تلقائياً لتطبيق «عيادة الجيب».
# المتغيرات المطلوبة (تُضاف في إعدادات البيئة، ولا تُكتب في الكود):
#   SUPABASE_ACCESS_TOKEN  رمز الوصول من supabase.com/dashboard/account/tokens
#   ANTHROPIC_API_KEY      (اختياري) مفتاح Claude من console.anthropic.com
#   ADMIN_EMAIL            (اختياري) بريد المدير بعد إنشاء حسابه في التطبيق
set -euo pipefail
REF="${SUPABASE_PROJECT_REF:-ifpduyrdexsbpyvcjjxz}"
SITE="${SITE_URL:-https://reshy0643-pixel.github.io/store/health/}"
CLI=(npx -y supabase@2.121.0)
cd "$(dirname "$0")/.."   # مجلد health
: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN غير موجود في متغيرات البيئة}"
export SUPABASE_ACCESS_TOKEN

echo "1/5 قاعدة البيانات…"
"${CLI[@]}" db query --project-ref "$REF" -f supabase/schema.sql >/dev/null

echo "2/5 إعدادات تسجيل الدخول…"
curl -fsS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d "{\"site_url\":\"$SITE\",\"uri_allow_list\":\"$SITE\"}" >/dev/null

echo "3/5 خادم الذكاء الاصطناعي…"
"${CLI[@]}" functions deploy ai --project-ref "$REF" --no-verify-jwt --use-api

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "4/5 مفتاح Claude…"
  tmp=$(mktemp); chmod 600 "$tmp"; trap 'rm -f "$tmp"' EXIT
  printf 'ANTHROPIC_API_KEY=%s\n' "$ANTHROPIC_API_KEY" > "$tmp"
  "${CLI[@]}" secrets set --project-ref "$REF" --env-file "$tmp" >/dev/null
else
  echo "4/5 تخطّي مفتاح Claude (ANTHROPIC_API_KEY غير موجود)"
fi

if [ -n "${ADMIN_EMAIL:-}" ]; then
  if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then echo "بريد المدير غير صالح"; exit 1; fi
  echo "5/5 تعيين المدير $ADMIN_EMAIL…"
  "${CLI[@]}" db query --project-ref "$REF" "update public.profiles set role='admin' where lower(email)=lower('$ADMIN_EMAIL') returning email"
else
  echo "5/5 تخطّي تعيين المدير (ADMIN_EMAIL غير موجود)"
fi
echo "تم الإعداد."
