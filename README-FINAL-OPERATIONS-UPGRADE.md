# Nityaseva — Operations Upgrade

This build is the operational upgrade for the existing Nityaseva Supabase app.

## Included
- Admin **+ Add Staff** shortcut and Staff assignment workspace.
- Care Executive **Visit Field App** from Today/Visits.
- Field visit status: Scheduled → Accepted → On the way → Arrived → In progress → Completed.
- Field checklist and notes saved to `visit_checklists`.
- Family Home visit tracker showing the same visit status.
- Family tracker refreshes automatically every 10 seconds.
- Paid subscription add-ons.
- Family report generation and sending handoff: in-app, email, WhatsApp.
- Senior code generated automatically. Admin does not type it.
- New code format: `NIT-YYYYMMDD-###` (example `NIT-20260913-004`). Serial is globally sequential.
- Full Nityaseva blue logo.

## Supabase migration
Run only:
`supabase/nityaseva_v4_operations.sql`

Do this on the existing Production database. Do not rerun the original base schema.

## Staff authentication
The Staff screen assigns existing authenticated staff profiles to seniors. Creating Auth accounts should be done through a secure invite/Edge Function, never with a service-role key in the browser.
