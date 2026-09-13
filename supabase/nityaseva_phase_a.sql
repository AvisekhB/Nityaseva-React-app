-- Nityaseva Phase A Operations Upgrade
-- Safe migration for the existing Nityaseva Production schema.
-- Run this ONCE in Supabase SQL Editor. Do not rerun the original base schema.

create extension if not exists pgcrypto;

-- =========================================================
-- 1. Senior 360 / Care Assessment
-- =========================================================
create table if not exists public.senior_assessments (
  id uuid primary key default gen_random_uuid(),
  senior_id uuid not null references public.seniors(id) on delete cascade,
  living_arrangement text,
  mobility_level text,
  eating_support text,
  bathing_support text,
  dressing_support text,
  walking_support text,
  toileting_support text,
  household_support text,
  family_contact_frequency text,
  social_isolation_risk text,
  home_stairs boolean,
  bathroom_safety text,
  lighting_safety text,
  emergency_access text,
  fall_hazards text,
  smartphone_access boolean,
  video_call_support boolean,
  assessment_notes text,
  assessed_by uuid references public.profiles(id),
  assessed_at timestamptz default now(),
  reviewed_at timestamptz,
  unique(senior_id)
);

alter table public.senior_assessments enable row level security;

drop policy if exists "senior_assessments_select" on public.senior_assessments;
create policy "senior_assessments_select" on public.senior_assessments
for select using (
  public.is_admin()
  or public.is_manager()
  or public.is_family_member(senior_id)
  or public.is_assigned_staff(senior_id)
);

drop policy if exists "senior_assessments_write" on public.senior_assessments;
create policy "senior_assessments_write" on public.senior_assessments
for all using (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
) with check (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
);

-- =========================================================
-- 2. Individual Care Plan
-- =========================================================
create table if not exists public.care_plans (
  id uuid primary key default gen_random_uuid(),
  senior_id uuid not null references public.seniors(id) on delete cascade,
  plan_status text not null default 'active',
  visit_frequency text,
  preferred_visit_time text,
  daily_needs text,
  food_preferences text,
  medication_support_requirements text,
  doctor_information text,
  emergency_instructions text,
  home_safety_requirements text,
  family_instructions text,
  special_assistance text,
  care_goals text,
  escalation_instructions text,
  review_date date,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(senior_id)
);

alter table public.care_plans enable row level security;

drop policy if exists "care_plans_select" on public.care_plans;
create policy "care_plans_select" on public.care_plans
for select using (
  public.is_admin()
  or public.is_manager()
  or public.is_family_member(senior_id)
  or public.is_assigned_staff(senior_id)
);

drop policy if exists "care_plans_write" on public.care_plans;
create policy "care_plans_write" on public.care_plans
for all using (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
) with check (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
);

-- =========================================================
-- 3. Staff onboarding / HR profile
-- =========================================================
create table if not exists public.staff_details (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  employee_code text unique,
  phone text,
  qualification text,
  skills text,
  joining_date date,
  employment_type text default 'contract',
  verification_status text default 'pending',
  id_document_status text default 'pending',
  background_check_status text default 'pending',
  availability_status text default 'available',
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(profile_id)
);

alter table public.staff_details enable row level security;

drop policy if exists "staff_details_select" on public.staff_details;
create policy "staff_details_select" on public.staff_details
for select using (public.is_admin() or public.is_manager() or profile_id = auth.uid());

drop policy if exists "staff_details_write" on public.staff_details;
create policy "staff_details_write" on public.staff_details
for all using (public.is_admin() or public.is_manager())
with check (public.is_admin() or public.is_manager());

-- =========================================================
-- 4. Family onboarding / consent fields
-- =========================================================
alter table public.family_members
  add column if not exists onboarding_status text default 'pending',
  add column if not exists consent_status text default 'pending',
  add column if not exists emergency_contact_name text,
  add column if not exists emergency_contact_phone text,
  add column if not exists onboarding_notes text,
  add column if not exists verified_at timestamptz;

-- =========================================================
-- 5. Visit verification
-- =========================================================
alter table public.visits
  add column if not exists checkin_at timestamptz,
  add column if not exists checkout_at timestamptz,
  add column if not exists checkin_latitude numeric,
  add column if not exists checkin_longitude numeric,
  add column if not exists checkout_latitude numeric,
  add column if not exists checkout_longitude numeric,
  add column if not exists location_verified boolean default false,
  add column if not exists senior_acknowledged boolean default false,
  add column if not exists acknowledgement_name text;

-- =========================================================
-- 6. Escalation engine
-- =========================================================
create table if not exists public.escalation_events (
  id uuid primary key default gen_random_uuid(),
  senior_id uuid not null references public.seniors(id) on delete cascade,
  visit_id uuid references public.visits(id) on delete set null,
  request_id uuid references public.service_requests(id) on delete set null,
  incident_id uuid references public.incidents(id) on delete set null,
  rule_code text not null,
  severity text not null default 'medium',
  status text not null default 'open',
  message text not null,
  assigned_to uuid references public.profiles(id),
  created_at timestamptz default now(),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  resolution_notes text
);

alter table public.escalation_events enable row level security;

drop policy if exists "escalation_events_select" on public.escalation_events;
create policy "escalation_events_select" on public.escalation_events
for select using (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
);

drop policy if exists "escalation_events_write" on public.escalation_events;
create policy "escalation_events_write" on public.escalation_events
for all using (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
) with check (
  public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id)
);

-- =========================================================
-- 7. Invoices / billing engine
-- =========================================================
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  senior_id uuid not null references public.seniors(id) on delete restrict,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  family_account_id uuid,
  billing_period_start date,
  billing_period_end date,
  subtotal numeric(12,2) not null default 0,
  addon_total numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  status text not null default 'pending',
  due_date date,
  paid_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

alter table public.invoices enable row level security;

drop policy if exists "invoices_select" on public.invoices;
create policy "invoices_select" on public.invoices
for select using (
  public.is_admin()
  or public.is_manager()
  or public.is_family_member(senior_id)
);

drop policy if exists "invoices_write" on public.invoices;
create policy "invoices_write" on public.invoices
for all using (public.is_admin() or public.is_manager())
with check (public.is_admin() or public.is_manager());

-- =========================================================
-- 8. Feedback
-- =========================================================
create table if not exists public.customer_feedback (
  id uuid primary key default gen_random_uuid(),
  senior_id uuid not null references public.seniors(id) on delete cascade,
  visit_id uuid references public.visits(id) on delete set null,
  family_user_id uuid references public.profiles(id) on delete set null,
  rating integer check (rating between 1 and 5),
  comment text,
  follow_up_required boolean default false,
  created_at timestamptz default now()
);

alter table public.customer_feedback enable row level security;

drop policy if exists "customer_feedback_select" on public.customer_feedback;
create policy "customer_feedback_select" on public.customer_feedback
for select using (
  public.is_admin() or public.is_manager() or public.is_family_member(senior_id)
);

drop policy if exists "customer_feedback_insert" on public.customer_feedback;
create policy "customer_feedback_insert" on public.customer_feedback
for insert with check (
  public.is_admin() or public.is_manager() or public.is_family_member(senior_id)
);

-- =========================================================
-- 9. Complaints
-- =========================================================
create table if not exists public.customer_complaints (
  id uuid primary key default gen_random_uuid(),
  complaint_number text not null unique,
  senior_id uuid not null references public.seniors(id) on delete cascade,
  family_user_id uuid references public.profiles(id) on delete set null,
  category text,
  description text not null,
  priority text default 'normal',
  status text default 'open',
  assigned_to uuid references public.profiles(id),
  due_at timestamptz,
  resolution text,
  customer_confirmed boolean default false,
  created_at timestamptz default now(),
  resolved_at timestamptz
);

alter table public.customer_complaints enable row level security;

drop policy if exists "customer_complaints_select" on public.customer_complaints;
create policy "customer_complaints_select" on public.customer_complaints
for select using (
  public.is_admin() or public.is_manager() or public.is_family_member(senior_id)
);

drop policy if exists "customer_complaints_write" on public.customer_complaints;
create policy "customer_complaints_write" on public.customer_complaints
for all using (
  public.is_admin() or public.is_manager() or public.is_family_member(senior_id)
) with check (
  public.is_admin() or public.is_manager() or public.is_family_member(senior_id)
);

-- =========================================================
-- 10. Notification preferences / event controls
-- =========================================================
create table if not exists public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  in_app boolean default true,
  email boolean default true,
  whatsapp boolean default false,
  sms boolean default false,
  visit_updates boolean default true,
  report_updates boolean default true,
  billing_updates boolean default true,
  emergency_updates boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id)
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_select" on public.notification_preferences;
create policy "notification_preferences_select" on public.notification_preferences
for select using (public.is_admin() or user_id = auth.uid());

drop policy if exists "notification_preferences_write" on public.notification_preferences;
create policy "notification_preferences_write" on public.notification_preferences
for all using (public.is_admin() or user_id = auth.uid())
with check (public.is_admin() or user_id = auth.uid());

-- =========================================================
-- 11. Indexes
-- =========================================================
create index if not exists idx_senior_assessments_senior on public.senior_assessments(senior_id);
create index if not exists idx_care_plans_senior on public.care_plans(senior_id);
create index if not exists idx_staff_details_profile on public.staff_details(profile_id);
create index if not exists idx_escalation_events_status on public.escalation_events(status, created_at desc);
create index if not exists idx_escalation_events_senior on public.escalation_events(senior_id);
create index if not exists idx_invoices_senior on public.invoices(senior_id);
create index if not exists idx_invoices_status on public.invoices(status);
create index if not exists idx_feedback_visit on public.customer_feedback(visit_id);
create index if not exists idx_complaints_senior on public.customer_complaints(senior_id);
create index if not exists idx_complaints_status on public.customer_complaints(status);

-- =========================================================
-- 12. Invoice serial generator
-- =========================================================
create sequence if not exists public.nityaseva_invoice_seq;

create or replace function public.generate_nityaseva_invoice_number()
returns text
language plpgsql
as $$
declare
  serial_no bigint;
begin
  serial_no := nextval('public.nityaseva_invoice_seq');
  return 'INV-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(serial_no::text, 5, '0');
end;
$$;

-- =========================================================
-- 13. Updated-at helper
-- =========================================================
create or replace function public.set_nityaseva_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_care_plans_updated_at on public.care_plans;
create trigger trg_care_plans_updated_at
before update on public.care_plans
for each row execute function public.set_nityaseva_updated_at();

drop trigger if exists trg_staff_details_updated_at on public.staff_details;
create trigger trg_staff_details_updated_at
before update on public.staff_details
for each row execute function public.set_nityaseva_updated_at();

drop trigger if exists trg_notification_preferences_updated_at on public.notification_preferences;
create trigger trg_notification_preferences_updated_at
before update on public.notification_preferences
for each row execute function public.set_nityaseva_updated_at();

-- =========================================================
-- End Phase A migration
-- =========================================================

-- =========================================================
-- 14. Organization settings
-- =========================================================
create table if not exists public.organization_settings (
  id uuid primary key default gen_random_uuid(),
  organization_name text not null default 'Nityaseva',
  tagline text default 'Eternal service, Timeless care.',
  support_phone text,
  support_email text,
  working_hours text default '08:00–20:00',
  default_visit_minutes integer default 60,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.organization_settings enable row level security;

drop policy if exists "organization_settings_select" on public.organization_settings;
create policy "organization_settings_select" on public.organization_settings
for select using (auth.uid() is not null);

drop policy if exists "organization_settings_write" on public.organization_settings;
create policy "organization_settings_write" on public.organization_settings
for all using (public.is_admin()) with check (public.is_admin());

drop trigger if exists trg_organization_settings_updated_at on public.organization_settings;
create trigger trg_organization_settings_updated_at
before update on public.organization_settings
for each row execute function public.set_nityaseva_updated_at();

insert into public.organization_settings (organization_name, tagline)
select 'Nityaseva', 'Eternal service, Timeless care.'
where not exists (select 1 from public.organization_settings);

-- =========================================================
-- 15. Complaint serial generator
-- =========================================================
create sequence if not exists public.nityaseva_complaint_seq;

create or replace function public.generate_nityaseva_complaint_number()
returns text
language plpgsql
as $$
declare
  serial_no bigint;
begin
  serial_no := nextval('public.nityaseva_complaint_seq');
  return 'CMP-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(serial_no::text, 4, '0');
end;
$$;

-- =========================================================
-- 16. Automatically create an invoice number when omitted
-- =========================================================
create or replace function public.set_nityaseva_invoice_number()
returns trigger
language plpgsql
as $$
begin
  if new.invoice_number is null or btrim(new.invoice_number) = '' then
    new.invoice_number := public.generate_nityaseva_invoice_number();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_invoices_number on public.invoices;
create trigger trg_invoices_number
before insert on public.invoices
for each row execute function public.set_nityaseva_invoice_number();

-- =========================================================
-- 17. Escalation indexes for operational scanning
-- =========================================================
create index if not exists idx_visits_operational_status on public.visits(scheduled_date, status);
create index if not exists idx_incidents_operational on public.incidents(created_at, severity);

-- End of Phase A migration.

-- =========================================================
-- 18. Authoritative senior code generator
-- Format: NIT-YYYYMMDD-0001, globally sequential serial.
-- =========================================================
create sequence if not exists public.nityaseva_senior_seq;

select setval(
  'public.nityaseva_senior_seq',
  coalesce((
    select max((regexp_match(customer_code, '^NIT-(?:[0-9]{8}-)?([0-9]+)$'))[1]::bigint)
    from public.seniors
    where customer_code ~ '^NIT-(?:[0-9]{8}-)?[0-9]+$'
  ), 0),
  true
);

create or replace function public.generate_nityaseva_senior_code()
returns text
language plpgsql
as $$
declare
  serial_no bigint;
begin
  serial_no := nextval('public.nityaseva_senior_seq');
  return 'NIT-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(serial_no::text, 4, '0');
end;
$$;

create or replace function public.set_nityaseva_senior_code()
returns trigger
language plpgsql
as $$
begin
  if new.customer_code is null or btrim(new.customer_code) = '' then
    new.customer_code := public.generate_nityaseva_senior_code();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_seniors_customer_code on public.seniors;
create trigger trg_seniors_customer_code
before insert on public.seniors
for each row execute function public.set_nityaseva_senior_code();

