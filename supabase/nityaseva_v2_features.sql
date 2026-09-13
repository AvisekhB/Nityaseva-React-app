-- Nityaseva feature upgrade v2
-- Run AFTER carenest_supabase_v1.sql and nityaseva_carenest_service_master_v3.sql.
-- Adds: automatic senior codes, subscription add-ons, report permissions and notification sending support.

begin;

-- 1. Automatic senior customer codes: NIT-001, NIT-002, ...
create sequence if not exists public.senior_customer_code_seq;

select setval(
  'public.senior_customer_code_seq',
  coalesce((
    select max(((regexp_match(customer_code, '^NIT-([0-9]+)$'))[1])::bigint)
    from public.seniors
    where customer_code ~ '^NIT-[0-9]+$'
  ), 1),
  true
);

create or replace function public.generate_senior_customer_code()
returns trigger
language plpgsql
security invoker
as $$
begin
  if new.customer_code is null or btrim(new.customer_code) = '' then
    new.customer_code := 'NIT-' || lpad(nextval('public.senior_customer_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generate_senior_customer_code on public.seniors;
create trigger trg_generate_senior_customer_code
before insert on public.seniors
for each row execute function public.generate_senior_customer_code();

-- 2. Subscription add-ons.
create table if not exists public.subscription_addons(
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete restrict,
  quantity int not null default 1 check(quantity > 0),
  unit_price numeric(12,2) not null default 0 check(unit_price >= 0),
  status text not null default 'active',
  added_at timestamptz default now(),
  notes text
);

create index if not exists idx_subscription_addons_subscription
  on public.subscription_addons(subscription_id, status);

alter table public.subscription_addons enable row level security;

drop policy if exists subscription_addons_access on public.subscription_addons;
create policy subscription_addons_access on public.subscription_addons
for select to authenticated
using(
  public.is_admin()
  or public.is_manager()
  or exists (
    select 1 from public.subscriptions s
    where s.id = subscription_addons.subscription_id
      and (s.family_account_id = auth.uid() or public.is_family_member(s.senior_id))
  )
);

drop policy if exists subscription_addons_manage on public.subscription_addons;
create policy subscription_addons_manage on public.subscription_addons
for all to authenticated
using(public.is_admin())
with check(public.is_admin());

-- 3. Family reports: allow admins/managers to create and linked families to read.
alter table public.family_reports enable row level security;

drop policy if exists family_reports_access on public.family_reports;
create policy family_reports_access on public.family_reports
for select to authenticated
using(
  public.is_admin()
  or public.is_manager()
  or public.is_family_member(senior_id)
);

drop policy if exists family_reports_manage on public.family_reports;
create policy family_reports_manage on public.family_reports
for all to authenticated
using(public.is_admin() or public.is_manager())
with check(public.is_admin() or public.is_manager());

-- 4. Admin/manager can send in-app report notifications to linked family accounts.
drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
for insert to authenticated
with check(public.is_admin() or public.is_manager());

commit;

-- Verification
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='subscription_addons'
order by ordinal_position;

select tgname
from pg_trigger
where tgrelid='public.seniors'::regclass
  and tgname='trg_generate_senior_customer_code';
