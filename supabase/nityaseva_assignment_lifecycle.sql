-- Nityaseva — Senior Assignment & Visit Lifecycle 1.0
-- Adds strict assignment lifecycle, scheduling/Gantt fields, cancellation workflow,
-- check-in/out and audit history. Run in Supabase SQL Editor.

begin;

alter table public.staff_assignments
  add column if not exists assignment_status text not null default 'unscheduled',
  add column if not exists scheduled_date date,
  add column if not exists scheduled_start_time time,
  add column if not exists scheduled_end_time time,
  add column if not exists estimated_duration_minutes integer default 60,
  add column if not exists service_name text,
  add column if not exists service_id text,
  add column if not exists special_instructions text,
  add column if not exists check_in_at timestamptz,
  add column if not exists check_in_latitude double precision,
  add column if not exists check_in_longitude double precision,
  add column if not exists staff_arrival_feedback text,
  add column if not exists completion_notes text,
  add column if not exists checklist_completed boolean not null default false,
  add column if not exists check_out_at timestamptz,
  add column if not exists check_out_latitude double precision,
  add column if not exists check_out_longitude double precision,
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid,
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid,
  add column if not exists closed_at timestamptz,
  add column if not exists closed_by uuid,
  add column if not exists cancellation_requested_at timestamptz,
  add column if not exists cancellation_requested_by uuid,
  add column if not exists cancellation_reason text,
  add column if not exists cancellation_notes text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid,
  add column if not exists cancellation_approval_notes text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Normalize existing assignments into the new lifecycle.
update public.staff_assignments
set assignment_status = case
  when active = false then 'cancelled'
  when scheduled_date is not null or start_date is not null then 'scheduled'
  else 'unscheduled'
end
where assignment_status is null
   or assignment_status = ''
   or assignment_status = 'unscheduled';

alter table public.staff_assignments
  drop constraint if exists staff_assignments_assignment_status_check;

alter table public.staff_assignments
  add constraint staff_assignments_assignment_status_check
  check (assignment_status in (
    'unscheduled','scheduled','in_progress','complete','close','cancellation','cancelled'
  ));

-- Fast filters and Gantt queries.
create index if not exists idx_staff_assignments_status
  on public.staff_assignments(assignment_status);
create index if not exists idx_staff_assignments_schedule
  on public.staff_assignments(scheduled_date, scheduled_start_time);
create index if not exists idx_staff_assignments_staff_schedule
  on public.staff_assignments(staff_id, scheduled_date, scheduled_start_time);

-- Status history / audit trail.
create table if not exists public.staff_assignment_status_history (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.staff_assignments(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id),
  changed_at timestamptz not null default now(),
  reason text,
  notes text
);

create index if not exists idx_staff_assignment_history_assignment
  on public.staff_assignment_status_history(assignment_id, changed_at desc);

-- Updated-at trigger.
create or replace function public.nityaseva_assignment_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_staff_assignments_updated_at on public.staff_assignments;
create trigger trg_staff_assignments_updated_at
before update on public.staff_assignments
for each row execute function public.nityaseva_assignment_updated_at();

-- Prevent overlapping scheduled work for the same staff member.
create or replace function public.nityaseva_check_assignment_overlap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assignment_status in ('scheduled','in_progress','complete','close')
     and new.scheduled_date is not null
     and new.scheduled_start_time is not null
     and new.scheduled_end_time is not null then
    if new.scheduled_end_time <= new.scheduled_start_time then
      raise exception 'Scheduled end time must be after start time';
    end if;

    if exists (
      select 1
      from public.staff_assignments a
      where a.staff_id = new.staff_id
        and a.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
        and a.assignment_status in ('scheduled','in_progress','complete','close')
        and a.scheduled_date = new.scheduled_date
        and a.scheduled_start_time is not null
        and a.scheduled_end_time is not null
        and new.scheduled_start_time < a.scheduled_end_time
        and new.scheduled_end_time > a.scheduled_start_time
    ) then
      raise exception 'Scheduling conflict: this staff member already has an overlapping assignment on %', new.scheduled_date;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_staff_assignments_no_overlap on public.staff_assignments;
create trigger trg_staff_assignments_no_overlap
before insert or update on public.staff_assignments
for each row execute function public.nityaseva_check_assignment_overlap();

-- Strict lifecycle and role enforcement.
create or replace function public.nityaseva_validate_assignment_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  actor_id uuid := auth.uid();
begin
  select role into actor_role from public.profiles where id = actor_id;

  if tg_op = 'INSERT' then
    if new.assignment_status is null then
      new.assignment_status := 'unscheduled';
    end if;
    return new;
  end if;

  if new.assignment_status = old.assignment_status then
    return new;
  end if;

  -- Admin/care-manager scheduling/reassignment.
  if old.assignment_status = 'unscheduled'
     and new.assignment_status = 'scheduled' then
    if actor_role not in ('super_admin','admin','care_manager') then
      raise exception 'Only admin, super admin or care manager can schedule an assignment';
    end if;
    if new.scheduled_date is null or new.scheduled_start_time is null then
      raise exception 'Scheduled date and start time are required';
    end if;
    return new;
  end if;

  -- Staff requests cancellation from an unscheduled/scheduled assignment.
  if old.assignment_status in ('unscheduled','scheduled')
     and new.assignment_status = 'cancellation' then
    if actor_id is null or actor_id <> new.staff_id then
      raise exception 'Only the assigned staff member can request cancellation';
    end if;
    new.cancellation_requested_at := coalesce(new.cancellation_requested_at, now());
    new.cancellation_requested_by := actor_id;
    return new;
  end if;

  -- Staff arrival check-in starts the visit.
  if old.assignment_status = 'scheduled'
     and new.assignment_status = 'in_progress' then
    if actor_id is null or actor_id <> new.staff_id then
      raise exception 'Only the assigned staff member can start the visit';
    end if;
    if new.check_in_at is null then
      new.check_in_at := now();
    end if;
    return new;
  end if;

  -- Staff completes only after check-in/checklist/check-out information exists.
  if old.assignment_status = 'in_progress'
     and new.assignment_status = 'complete' then
    if actor_id is null or actor_id <> new.staff_id then
      raise exception 'Only the assigned staff member can complete the visit';
    end if;
    if new.check_in_at is null then
      raise exception 'Check-in is required before completion';
    end if;
    if new.check_out_at is null then
      raise exception 'Check-out is required before completion';
    end if;
    if coalesce(new.checklist_completed, false) = false then
      raise exception 'All service checklist items must be completed before completion';
    end if;
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := actor_id;
    return new;
  end if;

  -- Admin/super admin verifies and closes.
  if old.assignment_status = 'complete'
     and new.assignment_status = 'close' then
    if actor_role not in ('super_admin','admin') then
      raise exception 'Only admin or super admin can close a completed service';
    end if;
    new.verified_at := coalesce(new.verified_at, now());
    new.verified_by := actor_id;
    new.closed_at := coalesce(new.closed_at, now());
    new.closed_by := actor_id;
    return new;
  end if;

  -- Super admin approves cancellation.
  if old.assignment_status = 'cancellation'
     and new.assignment_status = 'cancelled' then
    if actor_role <> 'super_admin' then
      raise exception 'Only super admin can approve final cancellation';
    end if;
    new.cancelled_at := coalesce(new.cancelled_at, now());
    new.cancelled_by := actor_id;
    new.active := false;
    return new;
  end if;

  -- Admin/care manager can reject a cancellation request and return it to scheduled.
  if old.assignment_status = 'cancellation'
     and new.assignment_status = 'scheduled' then
    if actor_role not in ('super_admin','admin','care_manager') then
      raise exception 'Only admin, super admin or care manager can reject a cancellation request';
    end if;
    if new.scheduled_date is null or new.scheduled_start_time is null then
      raise exception 'Scheduled date and start time are required';
    end if;
    return new;
  end if;

  raise exception 'Invalid assignment status transition: % -> %', old.assignment_status, new.assignment_status;
end;
$$;

drop trigger if exists trg_staff_assignments_validate_transition on public.staff_assignments;
create trigger trg_staff_assignments_validate_transition
before update on public.staff_assignments
for each row execute function public.nityaseva_validate_assignment_transition();

-- Automatically record every lifecycle transition.
create or replace function public.nityaseva_record_assignment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.staff_assignment_status_history
      (assignment_id, old_status, new_status, changed_by, reason, notes)
    values
      (new.id, null, new.assignment_status, auth.uid(), null, null);
  elsif new.assignment_status is distinct from old.assignment_status then
    insert into public.staff_assignment_status_history
      (assignment_id, old_status, new_status, changed_by, reason, notes)
    values
      (new.id, old.assignment_status, new.assignment_status, auth.uid(),
       new.cancellation_reason, new.cancellation_notes);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_staff_assignments_status_history on public.staff_assignments;
create trigger trg_staff_assignments_status_history
after insert or update on public.staff_assignments
for each row execute function public.nityaseva_record_assignment_status();

-- RLS for history.
alter table public.staff_assignment_status_history enable row level security;
drop policy if exists "authenticated can read assignment status history" on public.staff_assignment_status_history;
create policy "authenticated can read assignment status history"
on public.staff_assignment_status_history
for select to authenticated
using (true);

drop policy if exists "authenticated can insert assignment status history" on public.staff_assignment_status_history;
create policy "authenticated can insert assignment status history"
on public.staff_assignment_status_history
for insert to authenticated
with check (true);

commit;
