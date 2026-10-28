# EduDrishti architecture

## Current Stage 1 database foundation

Supabase Auth remains the identity provider. `public.profiles.user_id` is a one-to-one foreign key to `auth.users.id`; an `auth.users` insert trigger creates a profile with the `student` role. Signup metadata is used only for a bounded display name. Any submitted `role` or `app_role` field is ignored.

A trusted project operator provisions a teacher by updating `public.profiles.app_role` through the Supabase SQL Editor or another protected administrative path. Authenticated clients have update permission only for `display_name`; they cannot insert profiles or modify the role. There is no self-service teacher promotion flow.

## Data model

- `profiles` stores the application role and display name, not a duplicate email address.
- `classes` belongs to one teacher. `enrollments` is the class/student join table and carries enrollment status and provenance.
- `topics` stores subject, grade level, concept code, parent relationship, and metadata. A published Class 10 Mathematics `quadratic-equations` topic is seeded as public educational metadata.
- `questions` stores question text and options. `question_answer_keys` separately stores correct answers, grading configuration, and rationale so student question access cannot expose solutions.
- `assessments` belongs to a class. `assessment_questions` records each question's order and points.
- `assessment_attempts` belongs to a student and assessment. `responses` references the attempt and an actual question in that assessment; score fields are database constrained and writable only by trusted server-side code.
- `diagnoses` is tied to an assessment attempt and topic, keeping the evidence within the same student/class access boundary.
- `learning_sessions` and dated `progress_records` use the class/student enrollment relationship. Progress observations are append-oriented rather than overwriting one mutable mastery value.

The migration uses UUID keys, foreign keys, unique and check constraints, timestamps, and indexes for the expected ownership and reporting paths. It includes no report table; reports are derived from attempts, responses, diagnoses, sessions, and progress under the same RLS checks.

## Authorization boundary

All tables in the exposed `public` schema have RLS enabled. Grants are revoked from `PUBLIC`, `anon`, and `authenticated` first, then re-granted narrowly. The only unauthenticated read is for published topic metadata. Student reads are scoped to their own profiles, enrollments, attempts, responses, diagnoses, sessions, and progress. Teachers can read records only for classes they own and students linked to those classes. Class creation and enrollment use scoped database functions that derive the teacher identity from `auth.uid()` instead of trusting a client-supplied owner.

Students cannot write score, diagnosis, session, or progress fields directly. Assessment start, response save, and submission functions check the current student and assessment membership. Trusted Edge Functions or other server-side code using a server-only service credential remain responsible for grading and AI-derived records. Never expose a service-role key to the frontend.

Helper functions live in the non-API `private` schema, use a fixed empty `search_path`, and are `SECURITY DEFINER` only where needed to evaluate related-row authorization without recursive RLS. The local Supabase API config exposes only `public` and `graphql_public`.

## Frontend and AI integration

When Google Stitch source is supplied, inspect its framework before integration. The browser should use the Supabase URL and publishable/anon key. It should call the scoped database functions for class creation/enrollment and assessment participation. Grading, Gemini requests, diagnosis generation, and writes to score/progress data belong in authenticated Edge Functions. Validate identity, resource ownership, request sizes, and output schemas on the server.

## Student-data readiness

Use synthetic learner data during development. Before production student data is processed, define applicable consent, privacy, retention/deletion, and incident-response requirements. Class owner deletion and data retention need an explicit lifecycle workflow before self-service deletion is added.
