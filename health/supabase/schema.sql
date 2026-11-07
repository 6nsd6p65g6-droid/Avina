-- ============================================================
-- أفينا — قاعدة البيانات
-- انسخ هذا الملف كاملاً والصقه في: Supabase ← SQL Editor ← Run
-- يمكن تشغيله أكثر من مرة دون أن يفسد شيئاً.
-- ============================================================

-- ---------- الملفات الشخصية والأدوار ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

drop policy if exists "profiles_read" on public.profiles;
create policy "profiles_read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());

-- بريد المدير: من يسجّل به يصبح مديراً تلقائياً (جدول خاص لا يقرؤه التطبيق)
create table if not exists public.admin_emails (email text primary key);
alter table public.admin_emails enable row level security;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email, role) values (new.id, new.email,
    case when exists(select 1 from public.admin_emails a where lower(a.email) = lower(new.email)) then 'admin' else 'user' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
-- لمن سجّل قبل تشغيل هذا الملف
insert into public.profiles(id, email) select id, email from auth.users on conflict (id) do nothing;

-- ---------- بيانات المستخدم (الحفظ السحابي) ----------
create table if not exists public.user_state (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  constraint user_state_size check (octet_length(data::text) < 2000000)
);
alter table public.user_state enable row level security;
drop policy if exists "state_select" on public.user_state;
drop policy if exists "state_insert" on public.user_state;
drop policy if exists "state_update" on public.user_state;
drop policy if exists "state_delete" on public.user_state;
create policy "state_select" on public.user_state for select to authenticated using (user_id = auth.uid());
create policy "state_insert" on public.user_state for insert to authenticated with check (user_id = auth.uid());
create policy "state_update" on public.user_state for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "state_delete" on public.user_state for delete to authenticated using (user_id = auth.uid());

-- ---------- الخطط ----------
create table if not exists public.plans (
  id text primary key,
  name text not null,
  price_usd numeric(10,2) not null default 0,
  daily_ai int not null default 3,           -- عدد أسئلة الطبيب الذكي يومياً
  model text not null,                        -- نموذج الذكاء الاصطناعي لهذه الخطة
  can_generate boolean not null default false,-- كتابة مقالات جديدة في الموسوعة
  can_verify boolean not null default false,  -- المراجعة الثانية للدقة
  features jsonb not null default '[]',
  sort int not null default 0
);
alter table public.plans enable row level security;
drop policy if exists "plans_read" on public.plans;
drop policy if exists "plans_admin" on public.plans;
create policy "plans_read" on public.plans for select to anon, authenticated using (true);
create policy "plans_admin" on public.plans for update to authenticated using (public.is_admin()) with check (public.is_admin());
insert into public.plans (id, name, price_usd, daily_ai, model, can_generate, can_verify, features, sort) values
 ('free','مجاني',0,3,'claude-haiku-5-5',false,false,
  '["كل القياسات والفحوصات وزر الطوارئ","قراءة مقالات الموسوعة الجاهزة","3 أسئلة يومياً للطبيب الذكي","حفظ بياناتك في حسابك"]',1),
 ('pro','برو',5,30,'claude-haiku-5-5',true,true,
  '["كل مزايا المجاني","30 سؤالاً يومياً للطبيب الذكي","كتابة مقالات جديدة في الموسوعة","المراجعة الثانية للدقة"]',2),
 ('ultra','ألترا',10,15,'claude-opus-5-5',true,true,
  '["كل مزايا برو","الطبيب الخبير: أقوى نموذج ذكاء اصطناعي وأدقه","15 سؤالاً يومياً للطبيب الخبير","ملفات العائلة وقراءة التحاليل بالصورة (قريباً)"]',3)
on conflict (id) do nothing;

-- ---------- الإعدادات (يعدّلها المدير من لوحة التحكم) ----------
create table if not exists public.settings (
  key text primary key,
  value jsonb not null
);
alter table public.settings enable row level security;
drop policy if exists "settings_read" on public.settings;
drop policy if exists "settings_admin_ins" on public.settings;
drop policy if exists "settings_admin_upd" on public.settings;
create policy "settings_read" on public.settings for select to anon, authenticated using (true);
create policy "settings_admin_ins" on public.settings for insert to authenticated with check (public.is_admin());
create policy "settings_admin_upd" on public.settings for update to authenticated using (public.is_admin()) with check (public.is_admin());
insert into public.settings (key, value) values
 ('lyd_rate', '0'),        -- سعر الدولار بالدينار الليبي (0 = لم يُحدَّد بعد)
 ('card_markup', '0.2'),   -- زيادة كروت ليبيانا والمدار (0.2 = 20%)
 ('bank_info', '""'),      -- بيانات الحساب المصرفي للحوالات
 ('card_info', '""'),      -- تعليمات الدفع بالكروت
 ('support', '""'),        -- رقم واتساب أو هاتف للدعم
 ('paypal_link', '""'),    -- رابط PayPal (مثال: https://paypal.me/avina/{amount}USD)
 ('card_links', '{}')      -- روابط الدفع بالبطاقة لكل خطة ومدة، مثل {"pro:1":"https://buy.stripe.com/...?client_reference_id={ref}"}
on conflict (key) do nothing;

-- ---------- الاشتراكات ----------
create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null references public.plans(id),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.subscriptions enable row level security;
drop policy if exists "subs_read" on public.subscriptions;
create policy "subs_read" on public.subscriptions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------- طلبات الدفع ----------
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  email text,
  plan text not null references public.plans(id),
  months int not null check (months in (1,3,6,12)),
  method text not null check (method in ('transfer','libyana','madar','card','paypal')),
  amount_usd numeric(10,2),
  amount_lyd numeric(12,2),
  reference text check (char_length(reference) <= 200),
  cards text check (char_length(cards) <= 2000),
  receipt_path text check (char_length(receipt_path) <= 300),
  note text check (char_length(note) <= 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid
);
-- للقواعد المنشأة بنسخة أقدم: الدولة وطرق الدفع العالمية
alter table public.payments add column if not exists country text check (country ~ '^[A-Z]{2}$');
alter table public.payments add column if not exists provider_ref text check (char_length(provider_ref) <= 200);
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check check (method in ('transfer','libyana','madar','card','paypal'));
create index if not exists payments_status_idx on public.payments(status, created_at desc);
alter table public.payments enable row level security;
drop policy if exists "pay_insert" on public.payments;
drop policy if exists "pay_read" on public.payments;
create policy "pay_insert" on public.payments for insert to authenticated
  with check (user_id = auth.uid() and plan <> 'free');
create policy "pay_read" on public.payments for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- المبالغ تُحسب في الخادم، فلا يستطيع المستخدم تغييرها
create or replace function public.payments_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_price numeric; v_rate numeric; v_markup numeric; v_pending int;
begin
  select count(*) into v_pending from public.payments where user_id = auth.uid() and status = 'pending';
  if v_pending >= 3 then raise exception 'too_many_pending'; end if;
  select price_usd into v_price from public.plans where id = new.plan;
  if v_price is null or v_price <= 0 then raise exception 'invalid_plan'; end if;
  select coalesce((select (value #>> '{}')::numeric from public.settings where key = 'lyd_rate'), 0) into v_rate;
  select coalesce((select (value #>> '{}')::numeric from public.settings where key = 'card_markup'), 0.2) into v_markup;
  -- الطرق الليبية لليبيا فقط، والبطاقات وPayPal بالدولار
  if new.method in ('transfer','libyana','madar') and coalesce(new.country, 'LY') <> 'LY' then raise exception 'method_not_available'; end if;
  new.user_id := auth.uid();
  new.provider_ref := null;
  new.email := (select email from public.profiles where id = auth.uid());
  new.amount_usd := round(v_price * new.months, 2);
  new.amount_lyd := case when v_rate > 0 and new.method in ('transfer','libyana','madar') then
      round(v_price * new.months * v_rate * (case when new.method in ('libyana','madar') then 1 + v_markup else 1 end), 2)
    else null end;
  new.status := 'pending'; new.admin_note := null; new.reviewed_at := null; new.reviewed_by := null; new.created_at := now();
  return new;
end $$;
drop trigger if exists payments_before_insert on public.payments;
create trigger payments_before_insert before insert on public.payments
  for each row execute function public.payments_before_insert();

-- تفعيل الاشتراك أو تمديده (داخلية: يستدعيها المدير أو خادم الدفع فقط)
create or replace function public.activate_payment(p_id uuid, p_by uuid default null, p_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare p public.payments; s public.subscriptions; base timestamptz;
begin
  select * into p from public.payments where id = p_id for update;
  if not found or p.status <> 'pending' then raise exception 'not_pending'; end if;
  select * into s from public.subscriptions where user_id = p.user_id for update;
  if found and s.plan = p.plan and s.expires_at > now() then base := s.expires_at; else base := now(); end if;
  insert into public.subscriptions(user_id, plan, expires_at, updated_at)
    values (p.user_id, p.plan, base + make_interval(months => p.months), now())
    on conflict (user_id) do update set plan = excluded.plan, expires_at = excluded.expires_at, updated_at = now();
  update public.payments set status = 'approved', reviewed_at = now(), reviewed_by = p_by,
    provider_ref = coalesce(left(p_ref, 200), provider_ref) where id = p_id;
end $$;
revoke all on function public.activate_payment(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.activate_payment(uuid, uuid, text) to service_role;

-- الموافقة اليدوية من المدير
create or replace function public.approve_payment(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not_allowed'; end if;
  perform public.activate_payment(p_id, auth.uid(), null);
end $$;

create or replace function public.reject_payment(p_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not_allowed'; end if;
  update public.payments set status = 'rejected', admin_note = left(p_note, 500), reviewed_at = now(), reviewed_by = auth.uid()
    where id = p_id and status = 'pending';
  if not found then raise exception 'not_pending'; end if;
end $$;

-- منح اشتراك يدوياً (هدية أو تجربة)
create or replace function public.grant_plan(p_email text, p_plan text, p_months int) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_exp timestamptz;
begin
  if not public.is_admin() then raise exception 'not_allowed'; end if;
  select id into v_user from public.profiles where lower(email) = lower(trim(p_email));
  if v_user is null then raise exception 'user_not_found'; end if;
  if p_plan = 'free' then delete from public.subscriptions where user_id = v_user; return null; end if;
  if not exists(select 1 from public.plans where id = p_plan) then raise exception 'invalid_plan'; end if;
  insert into public.subscriptions(user_id, plan, expires_at, updated_at)
    values (v_user, p_plan, now() + make_interval(months => greatest(p_months, 1)), now())
    on conflict (user_id) do update set plan = excluded.plan, expires_at = excluded.expires_at, updated_at = now()
    returning expires_at into v_exp;
  return v_exp;
end $$;

-- ---------- استهلاك الذكاء الاصطناعي اليومي ----------
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  n int not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
drop policy if exists "usage_read" on public.ai_usage;
create policy "usage_read" on public.ai_usage for select to authenticated using (user_id = auth.uid() or public.is_admin());

create or replace function public.consume_ai(p_user uuid, p_limit int) returns int
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Africa/Tripoli')::date; v int;
begin
  if p_limit <= 0 then return null; end if;
  insert into public.ai_usage(user_id, day, n) values (p_user, d, 1)
  on conflict (user_id, day) do update set n = public.ai_usage.n + 1 where public.ai_usage.n < p_limit
  returning n into v;
  return v; -- null = انتهى الحد اليومي
end $$;
create or replace function public.refund_ai(p_user uuid) returns void
language sql security definer set search_path = public as $$
  update public.ai_usage set n = greatest(n - 1, 0)
  where user_id = p_user and day = (now() at time zone 'Africa/Tripoli')::date;
$$;
revoke execute on function public.consume_ai(uuid, int) from public, anon, authenticated;
revoke execute on function public.refund_ai(uuid) from public, anon, authenticated;
grant execute on function public.consume_ai(uuid, int) to service_role;
grant execute on function public.refund_ai(uuid) to service_role;

-- حالة اشتراكي (يقرؤها التطبيق)
create or replace function public.my_status() returns json
language sql stable security definer set search_path = public as $$
  with s as (select plan, expires_at from public.subscriptions where user_id = auth.uid() and expires_at > now()),
       p as (select * from public.plans where id = coalesce((select plan from s), 'free'))
  select json_build_object(
    'plan', p.id, 'name', p.name, 'expires_at', (select expires_at from s),
    'daily_ai', p.daily_ai, 'can_generate', p.can_generate, 'can_verify', p.can_verify,
    'used_today', coalesce((select n from public.ai_usage where user_id = auth.uid()
                            and day = (now() at time zone 'Africa/Tripoli')::date), 0),
    'is_admin', public.is_admin())
  from p;
$$;

-- ---------- الموسوعة الطبية المشتركة ----------
create table if not exists public.articles (
  topic text primary key,
  data jsonb not null,
  model text,
  verify jsonb,
  reviewed boolean not null default false,   -- يضعه المدير بعد مراجعة طبيب
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.articles enable row level security;
drop policy if exists "articles_read" on public.articles;
drop policy if exists "articles_admin_upd" on public.articles;
drop policy if exists "articles_admin_del" on public.articles;
create policy "articles_read" on public.articles for select to authenticated using (true);
create policy "articles_admin_upd" on public.articles for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "articles_admin_del" on public.articles for delete to authenticated using (public.is_admin());

-- ---------- صور إيصالات الحوالات ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg','image/png','image/webp','image/heic','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "receipts_upload_own" on storage.objects;
drop policy if exists "receipts_read" on storage.objects;
create policy "receipts_upload_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "receipts_read" on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ============================================================
-- بعد إنشاء حسابك في التطبيق، اجعل نفسك مديراً بتشغيل هذا السطر
-- (ضع بريدك مكان المثال):
--   update public.profiles set role = 'admin' where email = 'your@email.com';
-- ============================================================
