# ملاحظات المشروع

## المستودع
- الجذر: تطبيق إدارة المبيعات والمخزون (لا تعدّله إلا بطلب صريح).
- `health/`: تطبيق «عيادة الجيب» الصحي (PWA عربي)، منشور على GitHub Pages:
  https://reshy0643-pixel.github.io/store/health/
- خادم التطبيق على Supabase (مشروع `ifpduyrdexsbpyvcjjxz`): الملفات في `health/supabase/`
  (`schema.sql` و`functions/ai/index.ts` و`deploy.sh` ودليل عربي في `README.md`).

## عندما يقول المستخدم «بيئة»
يقصد إكمال إعداد **بيئة Claude السحابية «Reshy»** حتى يستطيع Claude تشغيل `health/supabase/deploy.sh`:
1. يفتح إعدادات البيئة: من السهم بجانب عنوان الجلسة ← **Edit cloud environment**،
   أو من claude.ai/code ← اختيار البيئة تحت مربع الكتابة ← أيقونة الترس بجانب «Reshy».
2. **Network access** ← **Custom** ← **Allowed domains**:
   `api.supabase.com` و`ifpduyrdexsbpyvcjjxz.supabase.co` و`reshy0643-pixel.github.io`،
   مع تفعيل **Also include default list of common package managers**.
3. **Environment variables**: `SUPABASE_ACCESS_TOKEN=sbp_...` و`ANTHROPIC_API_KEY=sk-ant-...`
   (رمز Supabase جديد، فالرمز القديم ظهر في المحادثة ويجب حذفه).
4. **Save changes**، ثم تُفتح جلسة جديدة (المتغيرات لا تُقرأ إلا في جلسة جديدة) وتشغّل:
   `ADMIN_EMAIL=reshy0643@gmail.com bash health/supabase/deploy.sh`
   ثم يُختبر الاتصال من التطبيق المنشور.
- لا تطلب من المستخدم لصق أي مفتاح سري في المحادثة.
- بريد المدير المقصود على الأرجح `reshy0643@gmail.com` (كتبه المستخدم `gmail.con`)؛ تأكّد منه قبل التشغيل.

## أسلوب العمل
- تحدّث مع المستخدم بالعربية فقط.
- اختبر قبل الرفع، ثم ارفع عبر طلب دمج إلى `main` (Pages ينشر من `main`).
