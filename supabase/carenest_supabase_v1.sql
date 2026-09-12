-- CareNest Senior Care | Supabase v1.0
-- Run in a fresh Supabase project's SQL Editor.
begin;
create extension if not exists pgcrypto;

DO $$ BEGIN CREATE TYPE public.app_role AS ENUM ('super_admin','admin','care_manager','care_executive','nurse','partner','family','senior'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
create type if not exists public.risk_level as enum ('green','yellow','red');
DO $$ BEGIN CREATE TYPE public.subscription_status AS ENUM ('trial','active','past_due','paused','cancelled','expired'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.visit_status AS ENUM ('scheduled','accepted','on_the_way','arrived','in_progress','completed','missed','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
create type if not exists public.priority_level as enum ('low','normal','high','critical');
create type if not exists public.incident_severity as enum ('low','medium','high','critical');

create table public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', phone text, email text, avatar_url text,
 role public.app_role not null default 'family',
 status text not null default 'active',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.service_zones(
 id uuid primary key default gen_random_uuid(), name text not null,
 city text not null, state text not null default 'West Bengal',
 pincode_list text[] default '{}', manager_id uuid references public.profiles(id),
 active boolean not null default true, created_at timestamptz default now()
);

create table public.partners(
 id uuid primary key default gen_random_uuid(), name text not null,
 partner_type text not null, contact_person text, phone text, email text,
 address text, service_area text, pricing_notes text, active boolean default true,
 created_at timestamptz default now()
);

create table public.seniors(
 id uuid primary key default gen_random_uuid(),
 customer_code text unique not null, full_name text not null,
 date_of_birth date, gender text, phone text, address text not null default '',
 city text not null default 'Asansol', state text not null default 'West Bengal',
 pincode text, latitude numeric(10,7), longitude numeric(10,7),
 living_status text, mobility_status text,
 risk_level public.risk_level not null default 'green',
 preferred_language text default 'Bengali', blood_group text,
 primary_doctor_id uuid references public.partners(id) on delete set null,
 preferred_hospital_id uuid references public.partners(id) on delete set null,
 zone_id uuid references public.service_zones(id) on delete set null,
 notes text, active boolean default true,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz default now(), updated_at timestamptz default now()
);

create table public.family_members(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid not null references public.seniors(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 relationship text not null, is_primary boolean default false,
 emergency_priority int default 1, notification_enabled boolean default true,
 unique(senior_id,user_id)
);

create table public.staff_assignments(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid not null references public.seniors(id) on delete cascade,
 staff_id uuid not null references public.profiles(id) on delete cascade,
 role public.app_role not null check(role in ('care_manager','care_executive','nurse')),
 start_date date default current_date, end_date date, active boolean default true,
 unique(senior_id,staff_id,role)
);

create table public.service_categories(
 id uuid primary key default gen_random_uuid(), name text unique not null,
 description text, active boolean default true, created_at timestamptz default now()
);

create table public.services(
 id uuid primary key default gen_random_uuid(),
 service_code text unique not null, service_name text not null,
 category_id uuid references public.service_categories(id) on delete set null,
 description text, customer_gets text, representative_does text,
 not_included text, escalation_rule text,
 price numeric(12,2), pricing_type text default 'included',
 duration_minutes int, requires_approval boolean default false,
 requires_professional boolean default false, active boolean default true,
 created_at timestamptz default now(), updated_at timestamptz default now()
);

create table public.service_plans(
 id uuid primary key default gen_random_uuid(), code text unique not null,
 name text not null, description text,
 single_price numeric(12,2) not null, couple_price numeric(12,2) not null,
 billing_cycle text default 'monthly', included_visits int default 0,
 active boolean default true, created_at timestamptz default now()
);

create table public.service_plan_inclusions(
 id uuid primary key default gen_random_uuid(),
 service_id uuid references public.services(id) on delete cascade,
 plan_code text not null check(plan_code in ('SAFE','CARE','PRIORITY')),
 included boolean default false, monthly_limit int,
 unique(service_id,plan_code)
);

create table public.subscriptions(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 family_account_id uuid references public.profiles(id) on delete set null,
 plan_id uuid references public.service_plans(id) on delete restrict,
 amount numeric(12,2) not null, start_date date default current_date,
 renewal_date date, status public.subscription_status default 'active',
 auto_renew boolean default true, cancellation_date date,
 created_at timestamptz default now(), updated_at timestamptz default now()
);

create table public.payments(
 id uuid primary key default gen_random_uuid(),
 subscription_id uuid references public.subscriptions(id) on delete set null,
 customer_id uuid references public.profiles(id) on delete set null,
 amount numeric(12,2) not null, payment_method text, transaction_id text,
 payment_date timestamptz, status text default 'pending',
 invoice_number text unique, notes text, created_at timestamptz default now()
);

create table public.visits(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 assigned_staff_id uuid references public.profiles(id) on delete set null,
 care_manager_id uuid references public.profiles(id) on delete set null,
 scheduled_date date not null, scheduled_start time, scheduled_end time,
 actual_start timestamptz, actual_end timestamptz,
 visit_type text default 'routine', status public.visit_status default 'scheduled',
 location_latitude numeric(10,7), location_longitude numeric(10,7),
 notes text, family_visible boolean default true,
 created_by uuid references public.profiles(id), created_at timestamptz default now(),
 updated_at timestamptz default now()
);

create table public.visit_checklists(
 id uuid primary key default gen_random_uuid(),
 visit_id uuid unique references public.visits(id) on delete cascade,
 wellbeing text, food_status text, hydration_status text, sleep_status text,
 medication_support text, daily_needs text, home_safety text,
 family_contact text, customer_request text, emergency_checked boolean default false,
 notes text, submitted_at timestamptz, created_at timestamptz default now()
);

create table public.health_readings(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 visit_id uuid references public.visits(id) on delete set null,
 recorded_by uuid references public.profiles(id) on delete set null,
 reading_type text not null, systolic numeric(6,2), diastolic numeric(6,2),
 pulse numeric(6,2), spo2 numeric(6,2), temperature numeric(6,2),
 glucose numeric(8,2), weight numeric(8,2), notes text,
 recorded_at timestamptz default now()
);

create table public.service_requests(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 service_id uuid references public.services(id) on delete set null,
 requested_by uuid references public.profiles(id) on delete set null,
 category text, title text not null, description text,
 priority public.priority_level default 'normal',
 assigned_to uuid references public.profiles(id) on delete set null,
 partner_id uuid references public.partners(id) on delete set null,
 status text default 'requested', estimated_cost numeric(12,2),
 actual_cost numeric(12,2), approval_required boolean default false,
 approved_by uuid references public.profiles(id), due_date timestamptz,
 completed_at timestamptz, created_at timestamptz default now(),
 updated_at timestamptz default now()
);

create table public.incidents(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 reported_by uuid references public.profiles(id) on delete set null,
 incident_type text not null, severity public.incident_severity default 'medium',
 description text not null, location text, action_taken text,
 emergency_called boolean default false, family_notified boolean default false,
 care_manager_notified boolean default false,
 hospital uuid references public.partners(id) on delete set null,
 resolved boolean default false, resolution_notes text,
 created_at timestamptz default now(), resolved_at timestamptz
);

create table public.emergency_events(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 initiated_by uuid references public.profiles(id),
 event_type text not null, started_at timestamptz default now(),
 emergency_service_called boolean default false, family_contacted boolean default false,
 care_manager_contacted boolean default false, ambulance_requested boolean default false,
 hospital_destination uuid references public.partners(id),
 status text default 'active', resolution text, created_at timestamptz default now(),
 resolved_at timestamptz
);

create table public.family_reports(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete cascade,
 report_type text not null, period_start date, period_end date,
 summary text, wellbeing_summary text, visit_summary text, health_summary text,
 service_summary text, incident_summary text, next_steps text,
 generated_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table public.notifications(
 id uuid primary key default gen_random_uuid(),
 user_id uuid references public.profiles(id) on delete cascade,
 senior_id uuid references public.seniors(id) on delete cascade,
 title text not null, message text not null, notification_type text not null,
 priority public.priority_level default 'normal', read boolean default false,
 created_at timestamptz default now()
);

create table public.complaints(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete restrict,
 submitted_by uuid references public.profiles(id), category text,
 description text not null, priority public.priority_level default 'normal',
 assigned_to uuid references public.profiles(id), status text default 'open',
 resolution text, created_at timestamptz default now(), closed_at timestamptz
);

create table public.feedback(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete cascade,
 user_id uuid references public.profiles(id), visit_id uuid references public.visits(id),
 rating int not null check(rating between 1 and 5), comment text,
 created_at timestamptz default now()
);

create table public.senior_safety_kits(
 id uuid primary key default gen_random_uuid(),
 senior_id uuid references public.seniors(id) on delete cascade,
 kit_code text unique not null, delivery_date date,
 bp_monitor boolean default false, pulse_oximeter boolean default false,
 thermometer boolean default false, glucometer boolean default false,
 medication_box boolean default false, health_diary boolean default false,
 emergency_card boolean default false, torch boolean default false,
 condition text, notes text, created_at timestamptz default now()
);

create table public.audit_logs(
 id uuid primary key default gen_random_uuid(),
 user_id uuid references public.profiles(id) on delete set null,
 action text not null, table_name text not null, record_id uuid,
 old_data jsonb, new_data jsonb, created_at timestamptz default now()
);

-- Indexes
create index idx_seniors_code on public.seniors(customer_code);
create index idx_seniors_risk on public.seniors(risk_level);
create index idx_family_user on public.family_members(user_id);
create index idx_assignment_staff on public.staff_assignments(staff_id,active);
create index idx_visits_date on public.visits(scheduled_date);
create index idx_visits_staff on public.visits(assigned_staff_id,scheduled_date);
create index idx_health_senior on public.health_readings(senior_id,recorded_at desc);
create index idx_requests_status on public.service_requests(status,priority);
create index idx_incidents_severity on public.incidents(severity,resolved);
create index idx_notifications_user on public.notifications(user_id,read,created_at desc);

-- Security helpers
create or replace function public.current_user_role()
returns public.app_role language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid(); $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.current_user_role() in ('super_admin','admin'),false); $$;

create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.current_user_role() in ('super_admin','admin','care_manager'),false); $$;

create or replace function public.is_family_member(p_senior uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.family_members where senior_id=p_senior and user_id=auth.uid()); $$;

create or replace function public.is_assigned_staff(p_senior uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.staff_assignments where senior_id=p_senior and staff_id=auth.uid() and active); $$;

-- Auth -> profile
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,full_name,email,phone)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.email,new.phone)
 on conflict(id) do nothing;
 return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- RLS
do $$ declare t text; begin
 foreach t in array array[
 'profiles','service_zones','partners','seniors','family_members',
 'staff_assignments','service_categories','services','service_plans',
 'service_plan_inclusions','subscriptions','payments','visits',
 'visit_checklists','health_readings','service_requests','incidents',
 'emergency_events','family_reports','notifications','complaints',
 'feedback','senior_safety_kits','audit_logs'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

create policy profiles_self_admin on public.profiles for select to authenticated
using(id=auth.uid() or public.is_admin());
create policy profiles_update_self_admin on public.profiles for update to authenticated
using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());

create policy seniors_access on public.seniors for select to authenticated
using(public.is_admin() or public.is_manager() or public.is_family_member(id) or public.is_assigned_staff(id));
create policy seniors_manage on public.seniors for all to authenticated
using(public.is_admin() or public.current_user_role()='care_manager')
with check(public.is_admin() or public.current_user_role()='care_manager');

create policy family_access on public.family_members for select to authenticated
using(public.is_admin() or user_id=auth.uid() or public.is_manager() or public.is_assigned_staff(senior_id));
create policy family_manage on public.family_members for all to authenticated
using(public.is_admin()) with check(public.is_admin());

create policy assignments_access on public.staff_assignments for select to authenticated
using(public.is_admin() or public.is_manager() or staff_id=auth.uid() or public.is_family_member(senior_id));
create policy assignments_manage on public.staff_assignments for all to authenticated
using(public.is_admin() or public.current_user_role()='care_manager')
with check(public.is_admin() or public.current_user_role()='care_manager');

create policy visits_access on public.visits for select to authenticated
using(public.is_admin() or public.is_manager() or assigned_staff_id=auth.uid() or care_manager_id=auth.uid() or public.is_family_member(senior_id));
create policy visits_create on public.visits for insert to authenticated
with check(public.is_admin() or public.is_manager());
create policy visits_update on public.visits for update to authenticated
using(public.is_admin() or public.is_manager() or assigned_staff_id=auth.uid())
with check(public.is_admin() or public.is_manager() or assigned_staff_id=auth.uid());

create policy health_access on public.health_readings for select to authenticated
using(public.is_admin() or public.is_manager() or recorded_by=auth.uid() or public.is_assigned_staff(senior_id) or public.is_family_member(senior_id));
create policy health_create on public.health_readings for insert to authenticated
with check(public.is_admin() or (public.current_user_role() in ('care_manager','care_executive','nurse') and public.is_assigned_staff(senior_id)));

create policy requests_access on public.service_requests for select to authenticated
using(public.is_admin() or public.is_manager() or requested_by=auth.uid() or assigned_to=auth.uid() or public.is_family_member(senior_id));
create policy requests_create on public.service_requests for insert to authenticated
with check(public.is_admin() or public.is_manager() or requested_by=auth.uid() or public.is_family_member(senior_id) or public.is_assigned_staff(senior_id));
create policy requests_update on public.service_requests for update to authenticated
using(public.is_admin() or public.is_manager() or assigned_to=auth.uid())
with check(public.is_admin() or public.is_manager() or assigned_to=auth.uid());

create policy incidents_access on public.incidents for select to authenticated
using(public.is_admin() or public.is_manager() or reported_by=auth.uid() or public.is_assigned_staff(senior_id) or public.is_family_member(senior_id));
create policy incidents_create on public.incidents for insert to authenticated
with check(public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id));

create policy emergency_access on public.emergency_events for select to authenticated
using(public.is_admin() or public.is_manager() or initiated_by=auth.uid() or public.is_assigned_staff(senior_id) or public.is_family_member(senior_id));
create policy emergency_create on public.emergency_events for insert to authenticated
with check(public.is_admin() or public.is_manager() or public.is_assigned_staff(senior_id) or public.is_family_member(senior_id));

create policy subscriptions_access on public.subscriptions for select to authenticated
using(public.is_admin() or public.is_manager() or family_account_id=auth.uid() or public.is_family_member(senior_id));
create policy subscriptions_manage on public.subscriptions for all to authenticated
using(public.is_admin()) with check(public.is_admin());

create policy notifications_self on public.notifications for select to authenticated
using(user_id=auth.uid() or public.is_admin());
create policy notifications_update on public.notifications for update to authenticated
using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());

-- Master data: authenticated users can read; admins manage.
create policy services_read on public.services for select to authenticated using(true);
create policy service_categories_read on public.service_categories for select to authenticated using(true);
create policy plans_read on public.service_plans for select to authenticated using(true);
create policy plan_inclusions_read on public.service_plan_inclusions for select to authenticated using(true);
create policy zones_read on public.service_zones for select to authenticated using(true);
create policy partners_read on public.partners for select to authenticated using(public.is_manager() or public.current_user_role()='partner');

create policy services_admin on public.services for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy categories_admin on public.service_categories for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy plans_admin on public.service_plans for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy inclusions_admin on public.service_plan_inclusions for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy zones_admin on public.service_zones for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy partners_admin on public.partners for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Seed pricing
insert into public.service_plans(code,name,description,single_price,couple_price,included_visits)
values
('SAFE','Safe','Basic peace-of-mind support',1799,2999,2),
('CARE','Care','Regular support and family visibility',3499,5499,4),
('PRIORITY','Priority','Closer monitoring and priority coordination',5999,8999,8);

insert into public.service_zones(name,city,state)
values('Asansol Central','Asansol','West Bengal'),
('Burnpur','Asansol','West Bengal'),('Kulti','Asansol','West Bengal'),
('Raniganj','Asansol','West Bengal');

insert into public.service_categories(name,description)
values
('Wellbeing','Senior wellbeing and routine checks'),
('Health','Health measurements and clinical coordination'),
('Medicine','Medicine support'),
('Essentials','Grocery and household support'),
('Appointments','Doctor and appointment coordination'),
('Hospital','Hospital coordination'),
('Emergency','Emergency coordination'),
('Mobility','Escort and physiotherapy'),
('Technology','Technology assistance'),
('Administration','Documents and bill assistance'),
('Care','Nursing and attendant coordination');

commit;

-- First Super Admin:
-- 1. Create the user in Supabase Authentication.
-- 2. Replace AUTH_USER_UUID below and run:
-- update public.profiles set role='super_admin' where id='AUTH_USER_UUID';
