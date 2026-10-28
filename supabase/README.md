# Supabase workspace

This directory contains the version-controlled PostgreSQL migration, local Supabase CLI configuration, and pgTAP database tests. The schema migration is additive: it creates application tables, functions, triggers, grants, indexes, RLS policies, and the initial published Quadratic Equations topic. It does not drop or alter Supabase-managed Auth tables.

## Link and run locally

1. Install the Supabase CLI and Docker Desktop.
2. Copy `.env.example` to `.env` and set `SUPABASE_PROJECT_REF` to the intended project reference. The project reference is not a credential.
3. Authenticate with `supabase login` (do not put the CLI access token in Git).
4. For local development, run `supabase start`, `supabase db reset`, and `supabase test db` from the repository root. The reset command targets only the local Docker database.
5. To link remote metadata, run `supabase link --project-ref "$SUPABASE_PROJECT_REF"`, then inspect `supabase migration list --linked` and the dashboard before any `supabase db push`.

The current configured project reference is `fdwnreumrodynvixoasl`. No secrets are stored in `config.toml` or the example environment file. `private` is intentionally excluded from exposed API schemas.

## Authentication and trusted writes

The migration installs an `AFTER INSERT` trigger on `auth.users`. It always creates a `student` profile and ignores role fields supplied in user metadata. New teachers require a trusted operator to update `public.profiles.app_role`; authenticated clients cannot update that column. A teacher creates a class through `public.create_class`, which sets `teacher_id` from the authenticated identity. Enrollment is performed through `public.enroll_student`, which verifies class ownership and student role.

Student assessment attempts are started through `public.start_assessment`; answers are saved through `public.save_response`; submission uses `public.submit_assessment`. These functions verify ownership and assessment membership. Direct writes to grading, diagnosis, learning-session, and progress data are restricted to trusted server-side code. Keep service-role credentials in server-side secret storage only.

## Tests and deployment status

`supabase/tests/rls.test.sql` is the PostgreSQL/pgTAP integration suite intended for the local database after migrations. It contains 57 assertions. Run it with `supabase test db`. `tests/test_database_migration.py` performs local static contract checks only; it is not a substitute for running PostgreSQL tests.

The additive migration is applied to the active Supabase project (`fdwnreumrodynvixoasl`) and recorded as migration version `20261028061647`. A separate remote transaction-scoped smoke test covered student isolation, teacher class boundaries, role escalation denial, trusted class/enrollment and assessment RPCs, and public-topic access. Its synthetic Auth and learning records were rolled back and remote counts confirmed cleanup. The pgTAP suite itself was not run locally because the Supabase CLI and `psql` are not installed on this computer.

The project was inspected before Stage 1: its `public` schema had no application tables and its migration list was empty. Do not use `supabase db reset` on a remote project; inspect and review migrations before remote deployment.

## Supabase references

- [Managing user data and Auth-triggered profile provisioning](https://supabase.com/docs/guides/auth/managing-user-data)
- [PostgreSQL Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
