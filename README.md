# EduDrishti Learner Intelligence

EduDrishti is an adaptive learning platform for students and teachers. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 2 extends the Supabase foundation with a backend-driven diagnostic assessment workflow, protected answer keys, deterministic server scoring, and student-owned results. It does not yet include the Google Stitch UI, Gemini integrations, or adaptive learning orchestration.

The seven-question Quadratic Equations diagnostic is explicitly labeled `development_fixture`; it is sample educational content, not an official exam and not learner-performance data. It covers factorisation, roots, discriminant/nature of roots, structured numeric/text responses, and a contextual problem.

The Stage 2 migration was applied to the configured EduDrishti Supabase project as migration version `20261028064819`. Transaction-scoped remote smoke tests exercised student and teacher paths and rolled back all synthetic users and records. See [supabase/README.md](supabase/README.md) for the exact validation limits.

## Stack and security boundaries

- Supabase Auth creates student profiles by default; teacher role provisioning remains trusted-operator only.
- Supabase PostgreSQL stores the application data with RLS, scoped write paths, and versioned migrations.
- Assessment questions are retrieved through RPCs rather than hardcoded into the future frontend. The client never supplies correctness or score values.
- Answer keys and post-submit explanations/misconception tags are stored separately and withheld until the student's attempt is graded.
- Service-role and Gemini credentials remain server-side only.

See [docs/architecture.md](docs/architecture.md), [docs/assessment-engine.md](docs/assessment-engine.md), and [supabase/README.md](supabase/README.md) for architecture, API contract, and migration workflow.

## Validation

Local Python checks:

```sh
python3 -m unittest discover -s tests -v
```

All 22 local Python tests passed. They are static contract and answer-arithmetic checks, not PostgreSQL execution. `supabase/tests/rls.test.sql` contains 86 pgTAP assertions, but the suite was not run: this computer has no Docker, `psql`, or Supabase CLI, and pgTAP is not installed on the remote database. Remote SQL smoke tests did pass through the Supabase connector, including answer privacy, validation, grading, retries, cross-student denial, teacher authoring, and authorized class access; all synthetic data was rolled back. These remote checks do not replace the pgTAP suite.

## Repository layout

```text
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
└── development.md

tests/
├── test_assessment_contract.py
├── test_database_migration.py
└── test_foundation.py
```
