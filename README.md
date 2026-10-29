# EduDrishti Learner Intelligence

EduDrishti is an adaptive learning platform for students and teachers. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 2 provides protected assessment data and deterministic server scoring. Stage 3 adds reviewed, evidence-linked misconception rules. Stage 4 adds three authenticated Supabase Edge Functions for personalized explanations, targeted practice, and practice-answer checking, backed by Gemini structured output and deterministic math validation. The Vercel-ready React UI remains under `web/`. Stage 3 and Stage 4 migrations/functions are source code until deployed; no AI key or live-provider validation is included. See [docs/ai-learning-services.md](docs/ai-learning-services.md) for endpoint contracts, security, secrets, tests, and limitations.

The seven-question Quadratic Equations diagnostic is explicitly labeled `development_fixture`; it is sample educational content, not an official exam and not learner-performance data. It covers factorisation, roots, discriminant/nature of roots, structured numeric/text responses, and a contextual problem.

The Stage 2 migration was applied to the configured EduDrishti Supabase project as migration version `20261028064819`. Transaction-scoped remote smoke tests exercised student and teacher paths and rolled back all synthetic users and records. See [supabase/README.md](supabase/README.md) for the exact validation limits.

## Stack and security boundaries

- Supabase Auth creates student profiles by default; teacher role provisioning remains trusted-operator only.
- Supabase PostgreSQL stores the application data with RLS, scoped write paths, and versioned migrations.
- The `web/` client retrieves assessment questions through RPCs rather than hardcoding the bank. It never supplies correctness or score values.
- Answer keys and post-submit explanations/misconception tags are stored separately and withheld until the student's attempt is graded.
- Service-role and Gemini credentials remain server-side only.

See [docs/architecture.md](docs/architecture.md), [docs/assessment-engine.md](docs/assessment-engine.md), [docs/ai-learning-services.md](docs/ai-learning-services.md), [docs/ui-deployment.md](docs/ui-deployment.md), and [supabase/README.md](supabase/README.md) for architecture, API contracts, Vercel setup, and migration workflow.

## Validation

Local deterministic checks:

```sh
node --experimental-strip-types --test supabase/functions/_shared/*.test.ts
python3 -m unittest discover -s tests -v
```

The Stage 4 local run passed 16 deterministic Node tests for handler flows, output validation, math consistency, target-operation/difficulty enforcement, answer-key withholding, and Supabase API-key headers, plus all 33 Python tests. The Python checks are static contracts and do not execute PostgreSQL. The existing pgTAP suite and new Stage 4 database permission tests were not run because the Supabase CLI and `psql` are unavailable on this computer (Docker is installed). No Gemini key was available, so live-provider behavior remains unverified. The Stage 4 migration and Edge Functions have not been deployed remotely.

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
│   ├── 20261028064819_stage2_diagnostic_assessment_engine.sql
│   ├── 20261028093000_stage3_misconception_engine.sql
│   └── 20261029222500_stage4_ai_learning_services.sql
├── functions/
│   ├── personalized-explanation/
│   ├── targeted-practice/
│   └── check-practice-answer/
└── tests/
    ├── rls.test.sql
    ├── diagnosis_engine.test.sql
    └── ai_learning_services.test.sql

docs/
├── architecture.md
├── assessment-engine.md
├── ai-learning-services.md
├── ui-deployment.md
└── development.md

tests/
├── test_ai_services_contract.py
├── test_assessment_contract.py
├── test_database_migration.py
└── test_foundation.py
```
