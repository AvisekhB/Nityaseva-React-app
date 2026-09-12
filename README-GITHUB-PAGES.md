# Nityaseva — GitHub Pages deployment

## Required GitHub setting
Open **Repository → Settings → Pages** and set **Source** to **GitHub Actions**.

Do not select **Deploy from a branch** for this workflow.

The workflow in `.github/workflows/deploy.yml` builds the Vite app and deploys `dist/` using the official GitHub Pages deployment actions.

## Repository variables/secrets
Under **Settings → Secrets and variables → Actions**:
- Repository variable: `VITE_SUPABASE_URL`
- Repository secret: `VITE_SUPABASE_ANON_KEY`

The browser must never contain a Supabase service-role/secret key.
