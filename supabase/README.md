# Supabase

Project ref: `suxohsmcgjzzllmyesgt` (https://suxohsmcgjzzllmyesgt.supabase.co)

- `migrations/` database changes, named `<14-digit timestamp>_<name>.sql`
- `functions/` edge functions (Deno); `_shared/` is code they import
- `config.toml` per-function JWT settings used when deploying
- `scripts/migrations.sh` migration-history helpers for the workflows

## GitHub Actions

`.github/workflows/supabase.yml` runs when anything under `supabase/` changes:

| When | What |
| --- | --- |
| Pull request | Checks migration names, lints and type-checks the functions, and lists the migrations the PR would apply |
| Push to `main` | The same checks, then `supabase db push` (new migrations only), then deploys every edge function |
| Actions tab > Supabase > Run workflow | Re-deploys from `main` |

A deploy stops before touching the database if the migration history isn't
set up (see the baseline below), so it can never re-run old migrations.

### One-time setup

1. **Secrets.** Repository Settings > Secrets and variables > Actions > New repository secret:
   - `SUPABASE_ACCESS_TOKEN`: a personal access token from
     https://supabase.com/dashboard/account/tokens
   - `SUPABASE_DB_URL`: Supabase dashboard > Connect > **Session pooler**
     connection string, with your database password filled in. Use the
     pooler, not the direct connection: GitHub runners don't have IPv6. If the
     password has symbols like `@`, `#` or `/`, percent-encode them.
2. **Baseline the history.** Migrations used to be applied by hand, so the
   database's history table doesn't match these files yet. In the Actions tab,
   run **Supabase baseline**:
   - first with *apply* off; check the plan it prints
   - then again with *apply* on.

   `pending` lists the migrations that have *not* been run on the database
   yet (default `20261018000000`, the specialties one). The next deploy runs
   them. The baseline only edits the history table; it runs no migration SQL.
3. Optional: Settings > Environments > `supabase-production` > add required
   reviewers to make every production deploy wait for approval.

### Adding a migration

Create `migrations/<YYYYMMDDHHMMSS>_<what_it_does>.sql` (or run
`supabase migration new <what_it_does>`), open a PR to see it in the preview,
and merge. Don't also apply it by hand in the SQL editor or with MCP: it would
then run twice.

Edge function secrets (`PAYNOW_*`, `FCM_SERVICE_ACCOUNT`, `WEBHOOK_SECRET`)
stay in the Supabase dashboard; the workflow doesn't touch them.
