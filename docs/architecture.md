# EduDrishti architecture

## Current foundation

EduDrishti uses Supabase Auth and PostgreSQL. The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations. Stage 2 adds a database-backed assessment engine; Stage 3 adds deterministic, reviewed-distractor diagnosis rules. Neither stage supplies AI-generated diagnosis or adaptive practice orchestration.

## Identity and roles

`public.profiles.user_id` is a one-to-one foreign key to `auth.users.id`. An Auth insert trigger creates every profile as `student` and ignores role claims in mutable user metadata. A trusted operator provisions teachers; authenticated clients may update only their display name and cannot promote themselves. Class ownership and enrollment are set through scoped database functions using `auth.uid()`.

## Data model

- `profiles` stores application role and display name, not a duplicate email address.
- `classes` belongs to one teacher. `enrollments` records class/student membership, status, and trusted provenance.
- `topics` stores subject, grade, concept code, hierarchy, and metadata. Published Class 10 Mathematics `quadratic-equations` metadata is seeded.
- `questions` stores prompt, type, answer options, topic, difficulty (1–5), concept, and content source. `question_answer_keys` stores correct-answer configuration separately. `question_guidance` stores explanations and misconception tags separately from student-readable question rows.
- `assessments` and `assessment_questions` define class assignments or explicitly marked development templates, ordered questions, and positive point weights.
- `assessment_attempts` belongs to one student and assessment. `responses` records submitted answers, timestamps, answered state, correctness, score percentage, points earned, and feedback.
- `diagnoses`, `learning_sessions`, and dated `progress_records` remain distinct protected learner records. Stage 3 generates a diagnosis only when an incorrect graded response matches an active, exact answer-pattern rule; unmatched errors remain unclassified. Stage 3 does not insert synthetic learner performance.

Schema changes are versioned in `supabase/migrations/`. Tables use UUID primary keys, foreign keys, checks, unique constraints, timestamps, and indexes. Exposed public tables use RLS and explicit grants.

## Assessment flow and scoring boundary

Authenticated students retrieve available assessments and question content through database RPCs. The browser does not receive answer keys, explanations, or misconception tags before completion. A published seven-item Quadratic Equations assessment is labeled `development_fixture` and can be taken by authenticated student profiles without inventing a teacher or class. Teacher-created assessments remain scoped to the teacher's own class and its active enrollments.

Students start through `public.start_assessment`, save strict JSON answers through `public.save_response`, and complete through `public.complete_assessment`. These server-side database functions check identity, role, assessment access, attempt ownership/state, question membership, and answer shape. They calculate correctness and points from protected answer keys; client-supplied scores are never accepted. Multiple-choice questions are all-or-nothing; numeric tolerance is stored server-side; normalized short-text matching is exact against accepted answers. Unanswered items are recorded at completion and earn zero. Completion is idempotent, and a completed student can intentionally start another numbered attempt. On the transition to `graded`, Stage 3 matches responses against protected rules and stores evidence-linked diagnoses in the same transaction.

`public.get_student_results` returns a versioned summary only to the student who owns a graded attempt. It then includes item correctness, points, correct answers, explanations, and misconception tags. `public.get_student_diagnoses` returns only that student's findings for a graded attempt. `public.get_class_misconception_summary` returns category counts only to the owning teacher and does not identify students. Teacher reads remain bounded by owned classes and enrolled students through the existing RLS rules; template attempts have no class owner and are visible only to their student.

## Authorization and API boundaries

All public application tables have RLS enabled. Grants are revoked from `PUBLIC`, `anon`, and `authenticated` before a narrow allowlist is applied. The only unauthenticated read is published topic metadata. Students can access only their own private learner records. Teachers can access only their owned classes and their enrolled students. Students cannot write attempt, response, score, guidance, answer-key, diagnosis, session, or progress records directly.

The `private` schema is not exposed by the Supabase Data API. Authorization helpers use a fixed empty `search_path`; `SECURITY DEFINER` is used only for scoped database checks and RPCs. Never expose the Supabase service-role key in browser code.

## Frontend and AI integration

When the Google Stitch source is supplied, inspect its framework before integration. Browser code should use the Supabase URL and publishable/anon key and call the documented RPCs in [assessment-engine.md](assessment-engine.md). Grading remains inside the database. Gemini requests, AI-generated diagnoses, and writes to downstream progress belong in trusted server-side code with strict input/output validation and server-only AI credentials.

## Student-data readiness

Use synthetic learner data during development. The seeded assessment/questions are educational fixtures, not learner records. Before production student data is processed, define applicable consent, privacy, retention/deletion, and incident-response requirements. Class-owner deletion and retention need an explicit lifecycle workflow before self-service deletion is added.
