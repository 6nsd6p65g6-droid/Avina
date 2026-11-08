#!/usr/bin/env bash
# إعداد Supabase تلقائياً لتطبيق «أفينا».
# المتغيرات المطلوبة (تُضاف في إعدادات البيئة، ولا تُكتب في الكود).
# الرمز يحتاج صلاحيات كتابة: database_write وauth_config_write وedge_functions_write وsecrets_write.
#   SUPABASE_ACCESS_TOKEN  رمز الوصول من supabase.com/dashboard/account/tokens
#   ANTHROPIC_API_KEY      (اختياري) مفتاح Claude من console.anthropic.com
#   ADMIN_EMAIL            (اختياري) بريد المدير بعد إنشاء حسابه في التطبيق
set -euo pipefail
REF="${SUPABASE_PROJECT_REF:-ifpduyrdexsbpyvcjjxz}"
SITE="${SITE_URL:-https://6nsd6p65g6-droid.github.io/Avina/health/}"
CLI=(npx -y supabase@2.121.0)
cd "$(dirname "$0")/.."   # مجلد health
: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN غير موجود في متغيرات البيئة}"
export SUPABASE_ACCESS_TOKEN

# استدعاء Management API مع عرض سبب الخطأ إن فشل
api(){ # api METHOD PATH [JSON_FILE]
  local out code; out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "https://api.supabase.com/v1/projects/$REF$2" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" ${3:+--data-binary @"$3"})
  if [ "${code:0:1}" != "2" ]; then echo "خطأ $code: $(head -c 400 "$out")" >&2; rm -f "$out"; exit 1; fi
  rm -f "$out"
}
sql(){ # يقرأ SQL من المدخل القياسي ويشغّله عبر API
  local f; f=$(mktemp)
  python3 -c 'import json,sys;print(json.dumps({"query":sys.stdin.read()}))' > "$f"
  api POST /database/query "$f"; rm -f "$f"
}

echo "1/5 قاعدة البيانات…"
sql < supabase/schema.sql

echo "2/5 إعدادات تسجيل الدخول…"
# روابط التأكيد واستعادة كلمة المرور تفتح الموقع (ومنه تعود إلى التطبيق)
auth=$(mktemp); printf '{"site_url":"%s","uri_allow_list":"%s,%sprivacy.html"}' "$SITE" "$SITE" "$SITE" > "$auth"
api PATCH /config/auth "$auth"; rm -f "$auth"

echo "3/5 الدوال: الذكاء الاصطناعي (ai) والدفع التلقائي (pay)…"
"${CLI[@]}" functions deploy ai --project-ref "$REF" --no-verify-jwt --use-api
"${CLI[@]}" functions deploy pay --project-ref "$REF" --no-verify-jwt --use-api

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
  printf "insert into public.admin_emails(email) values (lower('%s')) on conflict do nothing; update public.profiles set role='admin' where lower(email)=lower('%s');" "$ADMIN_EMAIL" "$ADMIN_EMAIL" | sql
else
  echo "5/5 تخطّي تعيين المدير (ADMIN_EMAIL غير موجود)"
fi
echo "تم الإعداد."
