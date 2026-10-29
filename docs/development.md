# Development guide

## Prerequisites and configuration

Install Git, Python 3, Docker Desktop, and the Supabase CLI for a full local PostgreSQL workflow. The repository targets PostgreSQL 17. Copy `.env.example` to the ignored `.env` file and replace secret placeholders only in that local file. `SUPABASE_PROJECT_REF` and `SUPABASE_URL` are project identifiers/endpoints, not credentials. Do not commit `.env`, access tokens, passwords, publishable keys, service-role keys, or Gemini keys.

`supabase/config.toml` configures the local project and API schemas. The `private` schema is intentionally not exposed. Supabase Auth providers and confirmation behavior remain Dashboard settings; migrations install the profile-provisioning trigger but do not change provider settings.

## Local workflow

From the repository root:

```sh
supabase start
supabase db reset
supabase test db
python3 -m unittest discover -s tests -v
```

`supabase db reset` resets only the local Docker-backed database and reapplies migrations. Never use a local reset command against a remote database. The pgTAP suite in `supabase/tests/rls.test.sql` contains 86 assertions covering constraints, role boundaries, answer validation, scoring, attempt transitions, and result privacy. Python tests are local static contract checks and answer arithmetic checks; they do not execute PostgreSQL or prove RLS behavior.

## Supabase project and remote workflow

The configured project reference is `fdwnreumrodynvixoasl`. Keep it in `.env` as `SUPABASE_PROJECT_REF`; it is not a credential. Authenticate the CLI without storing a token in the repository, then link and inspect the exact target:

```sh
supabase login
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list --linked
supabase db push
```

Before any remote push, confirm the project reference and migration ledger, inspect the SQL, and review the current remote schema/data. Do not run `supabase db reset` remotely. Avoid destructive migrations without explicit authorization. Keep service-role keys in server-side secret storage only.

Stage 2 migration version `20261028064819` has been applied to the configured EduDrishti project. Transaction-scoped remote SQL smoke tests passed for the student template flow, answer privacy/validation, deterministic scoring, incomplete/retry behavior, cross-student result isolation, teacher authoring/publication, and authorized class access. Their synthetic records were rolled back and verified absent. They are distinct from the pgTAP suite, which was not run: Docker is installed, but the current desktop lacks `psql` and the Supabase CLI; pgTAP is not installed on the remote database.

Stage 3 source is in `supabase/migrations/20261028093000_stage3_misconception_engine.sql`; it has not been applied to the remote project. It adds protected answer-pattern rules, same-transaction diagnosis generation on grading, and student/teacher-scoped diagnosis RPCs. Run `supabase test db` locally to execute `supabase/tests/diagnosis_engine.test.sql`; until the migration is applied, diagnosis and heatmap UI destinations remain unavailable.

## Stage 4 AI learning services

Stage 4 source is in `supabase/migrations/20261029222500_stage4_ai_learning_services.sql` and `supabase/functions/`. It is not deployed to the configured remote project. The functions validate the signed-in student, load only that student's graded assessment records, and store generated content and practice keys in private-schema tables through service-role-only RPCs. The Gemini API key belongs only in Supabase Edge Function secrets; use `supabase/functions/.env.example` as a placeholder template for local development and never commit the real `.env` file.

Run deterministic validation and mocked-handler/backend checks with `node --experimental-strip-types --test supabase/functions/_shared/*.test.ts`, static contracts with `python3 -m unittest discover -s tests -v`, and database permissions with `supabase test db` against a local stack. For a real Edge Function runtime, start the local stack and serve the functions with `supabase functions serve personalized-explanation targeted-practice check-practice-answer --env-file supabase/functions/.env`. No live Gemini request is considered verified until a test environment has a valid server-side key.

## Assessment API

See [assessment-engine.md](assessment-engine.md) for JSON input shapes, RPC parameters, SQLSTATE errors, result summary, answer privacy, retry semantics, and scoring rules. Students call `list_available_assessments`, `get_assessment`, `start_assessment`, `save_response`, `complete_assessment`, and `get_student_results` with their Supabase session. The server owns correctness and score calculation. Question explanations and misconception tags are withheld until a student requests their own completed results.

The seven-item Quadratic Equations assessment is labeled `development_fixture`. It is sample content, not an official exam, and no synthetic learner-performance rows are seeded. Class assessments still require an authorized teacher-owned class and an active student enrollment.

## Role provisioning and implementation rules

New Auth users become students even if user metadata claims another role. A trusted operator must verify a teacher and provision the role through the Supabase SQL Editor or another protected administrative path. Do not expose role-changing SQL through a browser endpoint. `public.create_class` derives ownership from the authenticated teacher; `public.enroll_student` checks class ownership and student role.

Put schema and policy changes in timestamped SQL migrations. Pair exposed-table RLS with explicit grants, keep answer keys and post-submit guidance separate from student-readable question rows, and use scoped RPCs for attempt lifecycle changes. Add allow and deny tests for each new policy. Review `git diff --check`, run the local checks available, and distinguish all local, remote, and unavailable validations in the delivery report.
