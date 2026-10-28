# EduDrishti Learner Intelligence

EduDrishti is an AI-powered adaptive learning platform that helps students identify learning gaps, get targeted explanations and practice, and helps teachers understand classroom learning needs. The initial domain is Class 10 Mathematics, beginning with Quadratic Equations.

## Current stage

Stage 1 establishes the Supabase PostgreSQL schema, Auth profile provisioning, database access controls, migrations, and security tests. It does not build the student/teacher UI, Gemini workflows, or later-stage learning features. The Google Stitch frontend will be integrated when supplied.

The additive Stage 1 migration is applied to the configured Supabase project (`fdwnreumrodynvixoasl`) and recorded remotely as version `20261028061647`. A remote, transaction-scoped RLS smoke test passed; its synthetic users and learning records were rolled back.

## Stack and security boundaries

- Supabase Auth provides identity. A database trigger creates every new profile as a student; signup metadata cannot assign a teacher role.
- Supabase PostgreSQL stores the application data. All exposed application tables have RLS enabled and explicit grants.
- Supabase Edge Functions or other trusted server-side code are responsible for grading and AI-derived diagnoses/progress. Service-role credentials must never be included in browser code.
- Vercel remains a possible frontend hosting target once the Stitch source is supplied.

See [docs/architecture.md](docs/architecture.md) for the data model and access boundaries, and [supabase/README.md](supabase/README.md) for migration and project-linking instructions.

## Database foundation

The migration creates profiles, classes, enrollments, topics, questions, private answer keys, assessments and assessment-question links, attempts, responses, diagnoses, learning sessions, and dated progress records. It also installs scoped class/enrollment/assessment RPCs, constraints, indexes, triggers, and RLS policies. The published Quadratic Equations topic is seeded. It does not create a report table; reports are assembled from protected learning records.

## Validation status

`python3 -m unittest discover -s tests -v` passes 13 local tests; these are static contract checks, not PostgreSQL execution. The 57-case pgTAP suite is committed under `supabase/tests/rls.test.sql` but was not run locally because the Supabase CLI and `psql` are unavailable. Separately, the remote smoke test exercised student and teacher RLS/RPC paths against Supabase PostgreSQL 17 and passed with transaction rollback; no fixture data remains.

`supabase db reset` is for the local Docker-backed database only. Follow [docs/development.md](docs/development.md) before linking or deploying to a remote project.

## Repository layout

```text
supabase/
├── config.toml
├── migrations/
│   └── 20261028061647_stage1_database_auth_rls.sql
└── tests/
    └── rls.test.sql

docs/
├── architecture.md
└── development.md

tests/
├── test_foundation.py
└── test_database_migration.py
```
