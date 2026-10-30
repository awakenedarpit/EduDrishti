# EduDrishti Learner Intelligence

EduDrishti is an adaptive learning platform for students and teachers. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 2 provides protected assessment data and deterministic server scoring. Stage 3 adds reviewed, evidence-linked misconception rules. Stage 4 adds authenticated server-side AI explanations and targeted practice. Stage 5 adds versioned progress snapshots, evidence-aware student progress/history/comparison RPCs, and owner-scoped aggregate teacher analytics. The `/progress`, `/reports`, and `/teacher/analytics` screens use real backend contracts with explicit empty states. Stage 3–5 migrations and Stage 4 functions remain source until deployed; the Stage 5 migration has not been applied remotely. See [docs/learning-progress.md](docs/learning-progress.md) for the `mastery-v1` formula and APIs, and [docs/ai-learning-services.md](docs/ai-learning-services.md) for AI service details.

The seven-question Quadratic Equations diagnostic is explicitly labeled `development_fixture`; it is sample educational content, not an official exam and not learner-performance data. It covers factorisation, roots, discriminant/nature of roots, structured numeric/text responses, and a contextual problem.

The Stage 2 migration was applied to the configured EduDrishti Supabase project as migration version `20261028064819`. Transaction-scoped remote smoke tests exercised student and teacher paths and rolled back all synthetic users and records. See [supabase/README.md](supabase/README.md) for the exact validation limits.

## Stack and security boundaries

- Supabase Auth creates student profiles by default; teacher role provisioning remains trusted-operator only.
- Supabase PostgreSQL stores the application data with RLS, scoped write paths, and versioned migrations.
- The `web/` client retrieves assessment questions through RPCs rather than hardcoding the bank. It never supplies correctness or score values.
- Answer keys and post-submit explanations/misconception tags are stored separately and withheld until the student's attempt is graded.
- Service-role and Gemini credentials remain server-side only.

See [docs/architecture.md](docs/architecture.md), [docs/assessment-engine.md](docs/assessment-engine.md), [docs/ai-learning-services.md](docs/ai-learning-services.md), [docs/learning-progress.md](docs/learning-progress.md), [docs/ui-deployment.md](docs/ui-deployment.md), and [supabase/README.md](supabase/README.md) for architecture, API contracts, Vercel setup, and migration workflow.

## Validation

Local deterministic checks:

```sh
node --experimental-strip-types --test supabase/functions/_shared/*.test.ts
python3 -m unittest discover -s tests -v
```

The earlier Stage 4 validation passed 16 deterministic Node tests and 33 Python tests; those Python tests are static contracts and do not execute PostgreSQL. No Gemini key was available, so live-provider behavior remains unverified. Stage 4 migrations and functions remain undeployed.

For Stage 5, all 44 Python repository tests passed. The frontend passed TypeScript (`pnpm typecheck`), all 9 Vitest tests, and the production build. `git diff --check` passed. The new pgTAP suite contains 40 assertions, but it was not executed because the Supabase CLI and `psql` are unavailable on this computer; no Stage 5 migration was applied remotely.

Frontend validation from `web/`:

```sh
pnpm typecheck
pnpm test
pnpm build
```

For Stage 5, TypeScript, all 9 web tests, and the Vercel production build passed. The existing route-manifest/SPA smoke check had previously returned all 23 routes. No remote Supabase calls or Vercel deployment were made.

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
│   ├── 20261028064819_stage2_diagnostic_assessment_engine.sql
│   ├── 20261028093000_stage3_misconception_engine.sql
│   ├── 20261029222500_stage4_ai_learning_services.sql
│   └── 20261030223000_stage5_learning_progress.sql
├── functions/
│   ├── personalized-explanation/
│   ├── targeted-practice/
│   └── check-practice-answer/
└── tests/
    ├── rls.test.sql
    ├── diagnosis_engine.test.sql
    ├── ai_learning_services.test.sql
    └── learning_progress.test.sql

docs/
├── architecture.md
├── assessment-engine.md
├── ai-learning-services.md
├── learning-progress.md
├── ui-deployment.md
└── development.md

tests/
├── test_ai_services_contract.py
├── test_assessment_contract.py
├── test_database_migration.py
├── test_learning_progress_contract.py
└── test_foundation.py
```
