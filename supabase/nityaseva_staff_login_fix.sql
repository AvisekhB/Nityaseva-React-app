-- Nityaseva staff login reliability fix
-- Run once in Supabase SQL Editor.
-- Staff can sign in with Email, Phone, or Employee Code.
-- GPS is intentionally NOT required during staff creation; it is captured later in the Staff app.

create or replace function public.nityaseva_resolve_login_identifier(p_identifier text)
returns text
language sql
security definer
set search_path = public
as $$
  select p.email
  from public.profiles p
  left join public.staff_details sd on sd.profile_id = p.id
  where p.status = 'active'
    and p.email is not null
    and (
      lower(trim(p.email)) = lower(trim(p_identifier))
      or regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g') = regexp_replace(trim(p_identifier), '[^0-9]', '', 'g')
      or upper(trim(coalesce(sd.employee_code,''))) = upper(trim(p_identifier))
    )
  order by case
    when lower(trim(p.email)) = lower(trim(p_identifier)) then 1
    when upper(trim(coalesce(sd.employee_code,''))) = upper(trim(p_identifier)) then 2
    else 3
  end
  limit 1;
$$;

grant execute on function public.nityaseva_resolve_login_identifier(text) to anon, authenticated;

alter table public.profiles add column if not exists must_change_password boolean not null default false;
alter table public.profiles add column if not exists email_verified boolean not null default false;
