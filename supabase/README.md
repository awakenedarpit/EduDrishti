# Supabase workspace

This directory contains the version-controlled PostgreSQL migrations, local Supabase CLI configuration, and pgTAP integration tests. Stage 1 provisions Auth profiles and the learning-domain schema. Stage 2 extends that foundation with assessment APIs, protected answer/grading data, and a clearly labeled development question bank. Migrations do not alter Supabase-managed Auth tables.

## Current configured project

The confirmed remote project is **EduDrishti** (`fdwnreumrodynvixoasl`). Stage 2 migration version `20261028064819` is applied there. Remote inspection confirmed RLS enabled on the application tables and exactly seven development questions, seven answer-key rows, seven guidance rows, and one development assessment. The assessment/response tables had no learner records before deployment.

Rollback-only remote smoke tests passed for student assessment listing/retrieval, pre-completion answer withholding, invalid question and answer rejection, idempotent start/save/completion, deterministic 5/7 scoring with one unanswered response, numeric tolerance, normalized short text, no partial credit, retry attempts, and denial of another student's results. A separate teacher/student smoke exercised a teacher-owned class, question/key/guidance authoring, publication checks, enrollment, student completion, and teacher access to that student's response. Synthetic Auth users, classes, questions, attempts, and responses were rolled back; post-test checks found none remaining.

The repository pgTAP file has 86 assertions, but was not executed. The desktop does not have Docker, `psql`, or the Supabase CLI; the remote database lists pgTAP as available but not installed. No extension was installed solely to run tests. Remote smoke checks are not a substitute for the pgTAP suite.

## Stage 3 misconception engine

The additive Stage 3 migration `20261028093000_stage3_misconception_engine.sql` installs protected, exact-answer-pattern rules and generates findings only for matched, incorrect, answered responses at grading time. It exposes `get_student_diagnoses` for a student's own completed attempt and `get_class_misconception_summary` for the owning teacher. Unmatched incorrect answers remain undiagnosed. The migration has not been applied to the configured remote project; its dedicated transaction-scoped pgTAP tests are in `supabase/tests/diagnosis_engine.test.sql`. See [../docs/misconception-engine.md](../docs/misconception-engine.md).

## Link and run locally

1. Install the Supabase CLI and Docker Desktop.
2. Copy `.env.example` to `.env` and set `SUPABASE_PROJECT_REF` to the intended project reference. The current non-secret reference is `fdwnreumrodynvixoasl`.
3. Authenticate with `supabase login`; do not put the CLI token in Git.
4. For local development, run `supabase start`, `supabase db reset`, and `supabase test db` from the repository root. Reset targets only the local Docker database.
5. Before linking or deploying remotely, confirm the project reference, run `supabase migration list --linked`, inspect the dashboard/schema and pending SQL, then use `supabase db push` only for the intended project.

The `private` schema is intentionally excluded from exposed API schemas. No credentials or service-role keys belong in `config.toml`, `.env.example`, or browser code.

## Authentication, authoring, and trusted writes

The Stage 1 `auth.users` trigger creates every profile as `student` and ignores role claims in user metadata. A trusted operator provisions teacher profiles. `public.create_class` sets class ownership from the authenticated teacher, and `public.enroll_student` validates ownership and student role.

Teachers author questions, separate answer keys, and protected guidance through their own RLS-scoped content paths. Only a complete draft with valid keys and guidance can be published. The Stage 2 `development_fixture` template and its sample keys/guidance are inserted by the migration; clients cannot claim this source or assign a teacher owner to those rows.

Students use `public.list_available_assessments`, `public.get_assessment`, `public.start_assessment`, `public.save_response`, `public.complete_assessment`, and `public.get_student_results`. Correct answers and explanations are withheld from the retrieval RPC and become available only through the owning student's completed-result RPC. The legacy `public.submit_assessment` remains a compatibility alias to the same server grading path.

See [../docs/assessment-engine.md](../docs/assessment-engine.md) for argument shapes, scoring, idempotency, error codes, and the result JSON contract.

## Tests and safety

Run the local Python contract checks with `python3 -m unittest discover -s tests -v`. They do not execute PostgreSQL. Run pgTAP through `supabase test db` against the local migrated Docker database once the CLI/Docker tools are available. Report remote smoke tests separately from both.

Before applying a migration, inspect the exact project and migration ledger. Stage 2 is additive and contains no `DROP` or `TRUNCATE`; it was applied only after confirming the project and empty assessment/response tables. Do not reset a remote database. See [../docs/development.md](../docs/development.md) for the safe workflow and validation limits.

## Supabase references

- [Auth-triggered user profile provisioning](https://supabase.com/docs/guides/auth/managing-user-data)
- [PostgreSQL Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Database functions and RPC](https://supabase.com/docs/guides/database/functions)
- [Supabase Data REST API](https://supabase.com/docs/guides/api/rest)
- [Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
