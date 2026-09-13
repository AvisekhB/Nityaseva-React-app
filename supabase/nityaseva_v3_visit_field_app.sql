-- Nityaseva visit field app + family live visit status
-- Run AFTER the base schema and nityaseva_v2_features.sql.

begin;

alter table public.visit_checklists enable row level security;

drop policy if exists visit_checklists_access on public.visit_checklists;
create policy visit_checklists_access on public.visit_checklists
for select to authenticated
using(
  public.is_admin()
  or public.is_manager()
  or exists (select 1 from public.visits v where v.id=visit_checklists.visit_id and (v.assigned_staff_id=auth.uid() or v.care_manager_id=auth.uid() or public.is_family_member(v.senior_id)))
);

drop policy if exists visit_checklists_staff_insert on public.visit_checklists;
create policy visit_checklists_staff_insert on public.visit_checklists
for insert to authenticated
with check(
  public.is_admin() or public.is_manager()
  or exists (select 1 from public.visits v where v.id=visit_checklists.visit_id and v.assigned_staff_id=auth.uid())
);

drop policy if exists visit_checklists_staff_update on public.visit_checklists;
create policy visit_checklists_staff_update on public.visit_checklists
for update to authenticated
using(
  public.is_admin() or public.is_manager()
  or exists (select 1 from public.visits v where v.id=visit_checklists.visit_id and v.assigned_staff_id=auth.uid())
)
with check(
  public.is_admin() or public.is_manager()
  or exists (select 1 from public.visits v where v.id=visit_checklists.visit_id and v.assigned_staff_id=auth.uid())
);

commit;
