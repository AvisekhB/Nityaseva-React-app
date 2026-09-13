-- Nityaseva Operations Upgrade v4
-- Run ONCE on the existing Nityaseva Production database.
-- Safe to re-run: uses IF EXISTS / IF NOT EXISTS and replaces policies/triggers.
-- Includes: date-stamped senior codes, subscription add-ons, report permissions,
-- notification insert permission, visit checklist RLS for the field app.

begin;

-- ============================================================
-- 1. Senior code: NIT-YYYYMMDD-###
-- Example: NIT-20260913-004
-- The numeric serial remains globally sequential; the date is the creation date.
-- ============================================================
create sequence if not exists public.senior_customer_code_seq;

select setval(
  'public.senior_customer_code_seq',
  coalesce((
    select max(((regexp_match(customer_code, '^NIT-(?:[0-9]{8}-)?([0-9]+)$'))[1])::bigint)
    from public.seniors
    where customer_code ~ '^NIT-(?:[0-9]{8}-)?[0-9]+$'
  ), 0),
  true
);

create or replace function public.generate_senior_customer_code()
returns trigger
language plpgsql
security invoker
as $$
begin
  if new.customer_code is null or btrim(new.customer_code) = '' then
    new.customer_code := 'NIT-' || to_char(current_date, 'YYYYMMDD') || '-' ||
      lpad(nextval('public.senior_customer_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generate_senior_customer_code on public.seniors;
create trigger trg_generate_senior_customer_code
before insert on public.seniors
for each row execute function public.generate_senior_customer_code();

-- ============================================================
-- 2. Paid subscription add-ons
-- ============================================================
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

-- ============================================================
-- 3. Family reports + in-app report notifications
-- ============================================================
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

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
for insert to authenticated
with check(public.is_admin() or public.is_manager());

-- ============================================================
-- 4. Care Executive field visit checklist RLS
-- ============================================================
alter table public.visit_checklists enable row level security;

drop policy if exists visit_checklists_access on public.visit_checklists;
create policy visit_checklists_access on public.visit_checklists
for select to authenticated
using(
  public.is_admin()
  or public.is_manager()
  or exists (
    select 1 from public.visits v
    where v.id = visit_checklists.visit_id
      and (
        v.assigned_staff_id = auth.uid()
        or v.care_manager_id = auth.uid()
        or public.is_family_member(v.senior_id)
      )
  )
);

drop policy if exists visit_checklists_staff_insert on public.visit_checklists;
create policy visit_checklists_staff_insert on public.visit_checklists
for insert to authenticated
with check(
  public.is_admin() or public.is_manager()
  or exists (
    select 1 from public.visits v
    where v.id = visit_checklists.visit_id
      and v.assigned_staff_id = auth.uid()
  )
);

drop policy if exists visit_checklists_staff_update on public.visit_checklists;
create policy visit_checklists_staff_update on public.visit_checklists
for update to authenticated
using(
  public.is_admin() or public.is_manager()
  or exists (
    select 1 from public.visits v
    where v.id = visit_checklists.visit_id
      and v.assigned_staff_id = auth.uid()
  )
)
with check(
  public.is_admin() or public.is_manager()
  or exists (
    select 1 from public.visits v
    where v.id = visit_checklists.visit_id
      and v.assigned_staff_id = auth.uid()
  )
);

commit;

-- Verification
select tgname
from pg_trigger
where tgrelid='public.seniors'::regclass
  and tgname='trg_generate_senior_customer_code';

select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='subscription_addons'
order by ordinal_position;
