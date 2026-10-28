# Development guide

## Current scope

The repository currently contains documentation and a lightweight foundation check only. There is no app runtime, dependency manifest, configured Supabase project, database schema, Edge Function, or Stitch frontend in this stage.

## Prerequisites

- Git for source control.
- Python 3 for the dependency-free foundation tests.
- Supabase CLI and a development Supabase project when database or Edge Function work begins.
- The runtime and package manager required by the supplied Stitch frontend, once its framework is known.

Do not install a frontend framework or backend dependency until the actual implementation needs are established.

## Environment variables and secrets

Use `.env.example` as a names-only/sample template. Make a local copy as needed:

```sh
cp .env.example .env
```

Replace placeholders only in the ignored local file. Never commit `.env`, paste secrets into source files, or use production credentials for local development. The Supabase service-role key and Gemini API key are server-only secrets; configure them in Supabase's Edge Function secret store when those functions exist. The frontend should receive only the Supabase URL and publishable/anon key.

## Validation

Run the standard-library tests from the repository root:

```sh
python3 -m unittest discover -s tests -v
```

Review the full diff and check that no local environment files, credentials, generated output, or unrelated files are staged before any commit. Once executable backend code is introduced, extend validation to include formatting/type checks appropriate to the chosen runtime, SQL migration checks, RLS tests (including unauthorized access cases), and Edge Function tests.

## Database and backend workflow (future)

1. Agree on entities, ownership, classroom membership, and authorization rules before schema design.
2. Create a reviewed, ordered SQL migration for each schema change; do not make undocumented dashboard-only changes.
3. Add RLS policies with deny-by-default behavior and tests for each role and access path.
4. Put privileged data operations and Gemini calls in Edge Functions. Validate JWTs, inputs, output schemas, and quotas server-side.
5. Use synthetic learner data in development and test environments.
6. Apply migrations and deploy functions to the intended Supabase environment only after review and authorization.

## Frontend integration workflow (future)

Wait for the Google Stitch-generated source. Inspect it before choosing integration steps, preserve its existing framework conventions, add only required dependencies, and connect it to documented Supabase contracts. Do not recreate or replace the frontend as part of Stage 0.

## Git and review workflow

Work on the agreed branch, use descriptive Conventional Commit messages, run checks before committing, inspect staged files, and never force-push or commit secrets. Push only after repository access and the target branch are confirmed.
