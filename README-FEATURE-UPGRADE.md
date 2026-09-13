# Nityaseva Feature Upgrade

This build adds the requested operational features:

- Add Staff assignment from the Staff workspace and header shortcut.
- Paid add-on services in Subscriptions using `subscription_addons`.
- Senior customer code is generated automatically in Supabase (`NIT-001`, `NIT-002`, ...); the form no longer asks the admin to type it.
- Family report generation plus in-app notification, email draft and WhatsApp handoff.
- Care Executive Visit Field App: live visit status, actual start/end, wellbeing, food, hydration, sleep, medication availability/support, daily needs, home safety, family communication, customer request, emergency check and field notes.
- Family Home live visit tracker that reads the visit status from Supabase and displays scheduled → accepted → on the way → arrived → in progress → completed.

## Supabase migration order

Run these after the existing base schema and service master:

1. `supabase/nityaseva_v2_features.sql`
2. `supabase/nityaseva_v3_visit_field_app.sql`

Do not rerun the original base schema on an existing production project.

## Important

Creating Supabase Auth staff accounts should be done with a secure admin invite/Edge Function. The browser must never contain a service-role key.
