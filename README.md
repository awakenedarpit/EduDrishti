# EduDrishti Learner Intelligence

EduDrishti is an adaptive learning platform for students and teachers. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 2 provides a backend-driven diagnostic assessment workflow, protected answer keys, deterministic server scoring, and student-owned results. This repository now also includes a Vercel-ready React UI under `web/`, adapted from the user-provided Stitch screens. Authentication, student assessment flow/reports, and teacher-owned class listing/creation use the existing Supabase backend. Every other Stitch destination remains a clearly labeled placeholder; diagnosis screens stay disconnected until the Stage 3 RPCs are deployed. Gemini integrations and adaptive learning orchestration are not included.

The seven-question Quadratic Equations diagnostic is explicitly labeled `development_fixture`; it is sample educational content, not an official exam and not learner-performance data. It covers factorisation, roots, discriminant/nature of roots, structured numeric/text responses, and a contextual problem.

The Stage 2 migration was applied to the configured EduDrishti Supabase project as migration version `20261028064819`. Transaction-scoped remote smoke tests exercised student and teacher paths and rolled back all synthetic users and records. See [supabase/README.md](supabase/README.md) for the exact validation limits.

## Stack and security boundaries

- Supabase Auth creates student profiles by default; teacher role provisioning remains trusted-operator only.
- Supabase PostgreSQL stores the application data with RLS, scoped write paths, and versioned migrations.
- The `web/` client retrieves assessment questions through RPCs rather than hardcoding the bank. It never supplies correctness or score values.
- Answer keys and post-submit explanations/misconception tags are stored separately and withheld until the student's attempt is graded.
- Service-role and Gemini credentials remain server-side only.

See [docs/architecture.md](docs/architecture.md), [docs/assessment-engine.md](docs/assessment-engine.md), [docs/ui-deployment.md](docs/ui-deployment.md), and [supabase/README.md](supabase/README.md) for architecture, API contract, Vercel setup, and migration workflow.

## Validation

Local Python checks:

```sh
python3 -m unittest discover -s tests -v
```

The 22 Stage 1/2 Python checks are static contract and answer-arithmetic tests, not PostgreSQL execution. `supabase/tests/rls.test.sql` contains 86 pgTAP assertions, but the suite was not run: this computer has no Docker, `psql`, or Supabase CLI, and pgTAP is not installed on the remote database. Remote Stage 2 SQL smoke tests did pass through the Supabase connector, including answer privacy, validation, grading, retries, cross-student denial, teacher authoring, and authorized class access; all synthetic data was rolled back. These remote checks do not replace the pgTAP suite.

Frontend validation from `web/`:

```sh
pnpm typecheck
pnpm test
pnpm build
```

For this UI change, TypeScript passed, all 9 web tests passed, the Vercel production build completed without bundle-size warnings, and the local HTTP smoke check returned the 23-route manifest plus the SPA shell for assessment and teacher deep links. No remote Supabase calls or Vercel deployment were made.

## Repository layout

```text
web/
├── package.json
├── pnpm-lock.yaml
├── public/manus-routes.json
├── src/
└── vercel.json

supabase/
├── config.toml
├── migrations/
│   ├── 20261028061647_stage1_database_auth_rls.sql
│   └── 20261028064819_stage2_diagnostic_assessment_engine.sql
└── tests/
    └── rls.test.sql

docs/
├── architecture.md
├── assessment-engine.md
├── ui-deployment.md
└── development.md

tests/
├── test_assessment_contract.py
├── test_database_migration.py
└── test_foundation.py
```
