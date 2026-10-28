# Stage 3: evidence-linked misconception diagnosis

Stage 3 adds deterministic, reviewed-distractor rules to the existing Stage 1/2 Supabase assessment model. The matcher does not use an AI provider and does not infer a learner's mental state from any arbitrary wrong answer. A diagnosis is created only when a graded, answered response exactly matches an active rule for that question. A wrong or unanswered response with no matching rule stays unclassified.

## Rule and finding model

Reviewed rules are stored in the non-exposed `private.misconception_rules` table. A rule binds one assessment question to an exact answer JSON pattern, a stable misconception code, an editor-assessed confidence value, and learner-facing explanation, corrective example, and follow-up question. The confidence value is not a calibrated probability and is not shown as one in the UI. The initial rules cover six discriminant, factor-pair, and sign distractors in the seeded Quadratic Equations fixture. Multiple-choice set matching is order-independent. Rule content is educational fixture content, not a validated psychometric assessment.

When an assessment attempt transitions to `graded`, a protected trigger evaluates its responses and inserts matched findings into the existing `public.diagnoses` table within the same transaction as grading. The evidence records the question, submitted and correct answer configuration, explanation, follow-up, and an explicit `rule_based` marker. Existing uniqueness makes diagnosis generation idempotent per attempt, topic, and code. A failed diagnosis insert also rolls back grading rather than leaving partially written results.

## RPCs

Students call `public.get_student_diagnoses(p_attempt_id uuid)` only for their own graded attempt, or `public.get_my_recent_diagnoses(p_limit integer default 10)` to list their recent findings. Teachers call `public.get_class_misconception_summary(p_class_id uuid, p_assessment_id uuid default null)` only for a class they own. The class summary reports distinct affected-student counts and matched evidence counts by topic and misconception code; it does not return student identities. The `/diagnosis` student route and `/teacher/misconceptions` teacher route are wired to these RPCs; both display an unavailable state if Stage 3 is not installed. All endpoints reject unauthorized requests, and direct table access remains limited by the existing RLS policies.

The rule engine is intentionally not a personalized explanation or adaptive-practice generator. It provides deterministic, evidence-linked findings from explicitly configured answer patterns; future stages may add teacher-reviewed rules, practice assignment, or a separately configured AI feature.

## Apply and validate

The additive migration is `supabase/migrations/20261028093000_stage3_misconception_engine.sql`. It inserts rule content for the existing development fixture and does not create learner records. A transaction-scoped pgTAP test at `supabase/tests/diagnosis_engine.test.sql` covers matched/unmatched answers, student ownership, and teacher class scope. Run locally with `supabase db reset` and `supabase test db`; run static checks with `python3 -m unittest discover -s tests -v`.

The migration is source code only until it is applied. No remote database was modified by this implementation. Before applying it to a Supabase project, verify the project reference and migration ledger, inspect the migration, and use the safe remote workflow in [development.md](development.md). The student and teacher routes require this migration in the connected database before returning data.
