# Nityaseva — Senior Care Platform v4

**Eternal service, Timeless care.**

Full pilot-stage web application with Supabase integration and role-based workflows.

## Built modules
1. Supabase database + RLS foundation
2. Authentication + role management
3. Admin dashboard
4. Senior & family management
5. Care Manager dashboard
6. Care Executive mobile dashboard
7. Visit/checklist foundation and visit scheduling
8. Service-request system
9. Health readings
10. Emergency/incident system
11. Family dashboard foundation
12. Subscriptions + payments
13. Reports + in-app notifications
14. GitHub Pages deployment

## Setup
Run `supabase/carenest_supabase_v1.sql`, then `supabase/carenest_service_master_v2.sql` in Supabase SQL Editor. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to `.env.local` locally or GitHub Actions variables/secrets.

**Never put the Supabase service-role/secret key in the browser.**

This is a pilot/MVP operational system. Before production, complete security review, backups, audit coverage, professional-service controls, payment gateway integration, notification delivery, file storage policies and end-to-end testing.

## Feature upgrade v2
Run `supabase/nityaseva_v2_features.sql` after the base schema and service master. It enables automatic NIT senior codes, subscription add-ons, family report permissions, and in-app report notifications.
