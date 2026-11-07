# ملاحظات المشروع

## المستودع
- الجذر: تطبيق إدارة المبيعات والمخزون (لا تعدّله إلا بطلب صريح).
- `health/`: تطبيق «عيادة الجيب» الصحي (PWA عربي)، منشور على GitHub Pages:
  https://reshy0643-pixel.github.io/store/health/
- خادم التطبيق على Supabase (مشروع `ifpduyrdexsbpyvcjjxz`): الملفات في `health/supabase/`
  (`schema.sql` و`functions/ai/index.ts` و`deploy.sh` ودليل عربي في `README.md`).

## عندما يقول المستخدم «بيئة»
يقصد إكمال إعداد **بيئة Claude السحابية «Reshy»** لتشغيل خادم التطبيق على Supabase.

**ما تمّ (7 نوفمبر 2026):**
- أُضيفت النطاقات `api.supabase.com` و`ifpduyrdexsbpyvcjjxz.supabase.co` و`reshy0643-pixel.github.io` إلى البيئة.
- تأكدنا: التطبيق منشور، والمفتاح العام صحيح، وتسجيل الدخول بالبريد مفعّل.
- لم تُنشأ قاعدة البيانات ولم تُنشر الدالة `ai` بعد.

**الخطوات الباقية:**
1. رمز Supabase: استدعِ `request_credential` للمضيف `api.supabase.com` (نوع bearer).
   - نموذج إدخال الرمز لا يظهر في تطبيق الهاتف (يظهر فقط «سماح/رفض»).
   - على المستخدم فتح الجلسة من claude.ai/code في المتصفح.
   - أو إضافة الرمز في إعدادات البيئة ← **Network secrets** للمضيف `api.supabase.com`.
2. بعد حفظ الرمز شغّل الإعداد برمز وهمي (الوكيل يستبدله بالحقيقي):
   `SUPABASE_ACCESS_TOKEN="sbp_$(printf '0%.0s' {1..40})" ADMIN_EMAIL=reshy0643@gmail.com bash health/supabase/deploy.sh`
3. مفتاح Claude يضعه المستخدم بنفسه في Supabase: **Edge Functions ← Secrets** باسم `ANTHROPIC_API_KEY`.
   لا يمرّ عبر هذه الجلسة.
4. اختبر:
   - `rest/v1/plans` يجب أن يعيد الخطط الثلاث.
   - `functions/v1/ai` بلا تسجيل دخول يجب أن يعيد 401.

- لا تطلب من المستخدم لصق أي مفتاح سري في المحادثة.
- الرمز القديم الذي ظهر في المحادثة يجب أن يُحذف من حساب Supabase.
- بريد المدير على الأرجح `reshy0643@gmail.com` (كتبه المستخدم `gmail.con`).

## أسلوب العمل
- تحدّث مع المستخدم بالعربية فقط.
- اختبر قبل الرفع، ثم ارفع عبر طلب دمج إلى `main` (Pages ينشر من `main`).
