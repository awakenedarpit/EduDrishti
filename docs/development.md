# Development guide

## Prerequisites and configuration

Install Git, Python 3, Docker Desktop, and the Supabase CLI. The repository targets PostgreSQL 17. Copy `.env.example` to the ignored `.env` file and replace secret placeholders only in that local file. `SUPABASE_PROJECT_REF` and `SUPABASE_URL` are project identifiers/endpoints, not credentials. Do not commit `.env`, access tokens, passwords, publishable keys, service-role keys, or Gemini keys.

The CLI's `supabase/config.toml` configures the local project and API schemas. The `private` schema is intentionally not exposed. The linked project's sign-up providers and email-confirmation behavior remain managed in the Supabase Dashboard; this migration adds the database profile-provisioning trigger but does not change dashboard Auth provider settings.

## Local workflow

From the repository root:

```sh
supabase start
supabase db reset
supabase test db
python3 -m unittest discover -s tests -v
```

`supabase db reset` resets only the local Docker-backed database and reapplies migrations. Never use a local reset command against a remote database. The pgTAP suite in `supabase/tests/` exercises constraints and authenticated-role access paths. The Python tests are local static contract checks; they do not execute SQL or prove database authorization.

## Remote project workflow

Authenticate the CLI without storing a token in the repository, then link the intended Supabase project:

```sh
supabase login
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list --linked
```

Review the migration list and current remote schema before deployment. The Stage 1 additive migration is already applied to the current project (`fdwnreumrodynvixoasl`) and recorded as version `20261028061647`; the local migration filename uses that same version. For future migrations, use `supabase db push` only after confirming the linked target and reviewing pending migrations. Do not use destructive migration statements without explicit authorization. Never expose the service-role key to the browser.

The current project was empty of application tables before Stage 1. A remote RLS smoke test passed in a transaction and rolled back all synthetic records. Remote test results are separate from local test results. The committed pgTAP suite was not run locally because the Supabase CLI and `psql` were unavailable on the development computer.

## Role provisioning

New Auth users become students even if their mutable user metadata claims another role. To provision a teacher, a trusted operator must verify the person's identity and use the Supabase SQL Editor or a protected administrative job to set `app_role = 'teacher'` on that user's profile. Do not expose role-changing SQL through a browser endpoint. Class ownership is assigned internally by `public.create_class`; clients cannot supply `teacher_id` directly.

## Database implementation rules

Put schema and policy changes in timestamped SQL migrations. Pair each exposed table's RLS policies with explicit grants. Keep answer keys separate from question content. Keep response grading, diagnoses, and progress writes in trusted server-side code. Add allow and deny tests for every new policy, run `supabase test db`, inspect the staged diff, then commit and push the reviewed change to the agreed branch.
