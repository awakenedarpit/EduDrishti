# EduDrishti Learner Intelligence

EduDrishti is an adaptive learning platform for students and teachers. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 2 provides a backend-driven diagnostic assessment workflow, protected answer keys, deterministic server scoring, and student-owned results. The repository includes a Vercel-ready React UI under `web/`; the separate Google Stitch frontend has not yet been supplied. Authentication, student assessment flow/reports, and teacher-owned class listing/creation use the existing Supabase backend. Other destinations remain placeholders or depend on migrations/functions not yet deployed.

Stage 6 adds authorized teacher analytics RPCs. A dashboard integration contract and OpenAPI specification are published at [docs/frontend-integration.md](docs/frontend-integration.md) and [docs/api/openapi.yaml](docs/api/openapi.yaml). These define stable Supabase interfaces without assuming Stitch's framework or component props.

## Security boundaries

- New Auth users are students; a trusted operator provisions teacher roles.
- PostgreSQL RLS and server-side RPC ownership checks are the authorization boundary.
- The browser uses only `VITE_SUPABASE_URL` and a publishable/anon key.
- Service-role/secret credentials and Gemini API keys remain server-side only.
- Assessment grading and supported rule-based diagnosis run in the database; client-supplied scores are never accepted.

## Validation

Run local Python contracts from the repository root:

```sh
python3 -m unittest discover -s tests -v
```

Run frontend checks from `web/`:

```sh
pnpm typecheck
pnpm test
pnpm build
```

The database's migration ledger, installed functions, RLS state, and deployment readiness are summarized in [docs/frontend-integration.md](docs/frontend-integration.md). Local static tests do not replace PostgreSQL/pgTAP execution.

## Repository layout

```text
web/         Vite + React + TypeScript browser client
supabase/    PostgreSQL migrations, RLS tests and local configuration
docs/api/    OpenAPI 3.1 specification
docs/        architecture and integration contracts
tests/       static migration/API tests
```
