-- Stage 5 progress model, history, comparison, and authorization tests.
-- All identities and source records are transaction-scoped and rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(40) LIMIT 1;

INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
) VALUES
    ('61000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'progress-a@test.invalid', '', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'progress-b@test.invalid', '', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'progress-other@test.invalid', '', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-0000-0000-000000000010', 'authenticated', 'authenticated', 'progress-teacher-a@test.invalid', '', '{}', '{}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'progress-teacher-b@test.invalid', '', '{}', '{}', pg_catalog.now(), pg_catalog.now());
UPDATE public.profiles SET app_role = 'teacher'
WHERE user_id IN ('61000000-0000-0000-0000-000000000010', '61000000-0000-0000-0000-000000000011');

INSERT INTO public.classes (id, teacher_id, name, grade_level, subject) VALUES
    ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000010', 'Progress Class A', 10, 'Mathematics'),
    ('62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000011', 'Progress Class B', 10, 'Mathematics');
INSERT INTO public.enrollments (class_id, student_id, created_by_teacher_id) VALUES
    ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000010'),
    ('62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000003', '61000000-0000-0000-0000-000000000011');

INSERT INTO public.questions (id, author_teacher_id, topic_id, question_type, prompt, options, concept) VALUES
    ('63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 1', '[]'::jsonb, 'factorisation_roots'),
    ('63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 2', '[]'::jsonb, 'factorisation_roots'),
    ('63000000-0000-0000-0000-000000000003', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 3', '[]'::jsonb, 'factorisation_roots'),
    ('63000000-0000-0000-0000-000000000004', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 4', '[]'::jsonb, 'factorisation_roots'),
    ('63000000-0000-0000-0000-000000000005', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 5', '[]'::jsonb, 'factorisation_roots'),
    ('63000000-0000-0000-0000-000000000006', '61000000-0000-0000-0000-000000000010', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Progress test item 6', '[]'::jsonb, 'discriminant_nature'),
    ('63000000-0000-0000-0000-000000000011', '61000000-0000-0000-0000-000000000011', (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), 'numeric', 'Unrelated class item', '[]'::jsonb, 'factorisation_roots');

INSERT INTO public.assessments (id, class_id, created_by_teacher_id, title, assessment_type, status) VALUES
    ('64000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000010', 'Progress assessment A', 'diagnostic', 'published'),
    ('64000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000011', 'Unrelated assessment B', 'diagnostic', 'published');
INSERT INTO public.assessment_questions (assessment_id, question_id, position, points)
SELECT '64000000-0000-0000-0000-000000000001', question_id, (row_number() OVER (ORDER BY question_id))::integer, 1
FROM (VALUES
    ('63000000-0000-0000-0000-000000000001'::uuid), ('63000000-0000-0000-0000-000000000002'::uuid),
    ('63000000-0000-0000-0000-000000000003'::uuid), ('63000000-0000-0000-0000-000000000004'::uuid),
    ('63000000-0000-0000-0000-000000000005'::uuid), ('63000000-0000-0000-0000-000000000006'::uuid)
) AS selected(question_id);
INSERT INTO public.assessment_questions (assessment_id, question_id, position, points)
VALUES ('64000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000011', 1, 1);

INSERT INTO public.assessment_attempts (id, assessment_id, student_id, attempt_number, status, started_at, submitted_at) VALUES
    ('65000000-0000-0000-0000-000000000001', '64000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 1, 'submitted', pg_catalog.now() - INTERVAL '46 days', pg_catalog.now() - INTERVAL '45 days'),
    ('65000000-0000-0000-0000-000000000002', '64000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 2, 'submitted', pg_catalog.now() - INTERVAL '36 days', pg_catalog.now() - INTERVAL '35 days'),
    ('65000000-0000-0000-0000-000000000003', '64000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 3, 'submitted', pg_catalog.now() - INTERVAL '3 days', pg_catalog.now() - INTERVAL '2 days'),
    ('65000000-0000-0000-0000-000000000004', '64000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 4, 'submitted', pg_catalog.now() - INTERVAL '2 days', pg_catalog.now() - INTERVAL '1 day'),
    ('65000000-0000-0000-0000-000000000011', '64000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000003', 1, 'submitted', pg_catalog.now() - INTERVAL '1 day', pg_catalog.now() - INTERVAL '1 day');

INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer, answered_at, score_percent, is_correct, graded_at, is_answered, points_earned)
SELECT attempt.id,
       attempt.assessment_id,
       selected.question_id,
       '{}'::jsonb,
       attempt.submitted_at,
       CASE WHEN selected.is_correct THEN 100 ELSE 0 END,
       selected.is_correct,
       attempt.submitted_at,
       true,
       CASE WHEN selected.is_correct THEN 1 ELSE 0 END
FROM public.assessment_attempts AS attempt
CROSS JOIN LATERAL (
    SELECT response.question_id, response.is_correct
    FROM (VALUES
        ('65000000-0000-0000-0000-000000000001'::uuid, '63000000-0000-0000-0000-000000000001'::uuid, true),
        ('65000000-0000-0000-0000-000000000001'::uuid, '63000000-0000-0000-0000-000000000002'::uuid, true),
        ('65000000-0000-0000-0000-000000000001'::uuid, '63000000-0000-0000-0000-000000000003'::uuid, true),
        ('65000000-0000-0000-0000-000000000002'::uuid, '63000000-0000-0000-0000-000000000001'::uuid, true),
        ('65000000-0000-0000-0000-000000000002'::uuid, '63000000-0000-0000-0000-000000000002'::uuid, true),
        ('65000000-0000-0000-0000-000000000002'::uuid, '63000000-0000-0000-0000-000000000003'::uuid, true),
        ('65000000-0000-0000-0000-000000000003'::uuid, '63000000-0000-0000-0000-000000000001'::uuid, true),
        ('65000000-0000-0000-0000-000000000003'::uuid, '63000000-0000-0000-0000-000000000002'::uuid, true),
        ('65000000-0000-0000-0000-000000000003'::uuid, '63000000-0000-0000-0000-000000000003'::uuid, true),
        ('65000000-0000-0000-0000-000000000004'::uuid, '63000000-0000-0000-0000-000000000004'::uuid, true),
        ('65000000-0000-0000-0000-000000000004'::uuid, '63000000-0000-0000-0000-000000000005'::uuid, false),
        ('65000000-0000-0000-0000-000000000004'::uuid, '63000000-0000-0000-0000-000000000006'::uuid, false),
        ('65000000-0000-0000-0000-000000000011'::uuid, '63000000-0000-0000-0000-000000000011'::uuid, false)
    ) AS response(attempt_id, question_id, is_correct)
    WHERE response.attempt_id = attempt.id
) AS selected;

DO $$
DECLARE
    attempt record;
BEGIN
    FOR attempt IN
        SELECT id, submitted_at
        FROM public.assessment_attempts
        WHERE id IN (
            '65000000-0000-0000-0000-000000000001', '65000000-0000-0000-0000-000000000002',
            '65000000-0000-0000-0000-000000000003', '65000000-0000-0000-0000-000000000004',
            '65000000-0000-0000-0000-000000000011'
        )
        ORDER BY submitted_at, id
    LOOP
        UPDATE public.assessment_attempts
        SET status = 'graded', score_percent = CASE WHEN attempt.id = '65000000-0000-0000-0000-000000000004' THEN 33.33 ELSE 100 END
        WHERE id = attempt.id;
    END LOOP;
END;
$$;

INSERT INTO private.ai_learning_activities (
    id, student_id, attempt_id, question_id, activity_type, model, prompt_version, content, created_at
) VALUES (
    '66000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000001',
    '65000000-0000-0000-0000-000000000003',
    '63000000-0000-0000-0000-000000000001',
    'practice', 'test-model', 'pgtap-v1',
    '{"items":[{"id":"67000000-0000-0000-0000-000000000001"},{"id":"67000000-0000-0000-0000-000000000002"},{"id":"67000000-0000-0000-0000-000000000003"}]}'::jsonb,
    pg_catalog.now() - INTERVAL '2 days'
);
INSERT INTO private.ai_practice_responses (student_id, activity_id, item_id, submitted_answer, is_correct, created_at) VALUES
    ('61000000-0000-0000-0000-000000000001', '66000000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000001', '{"selected_option":"A"}'::jsonb, true, pg_catalog.now() - INTERVAL '2 days'),
    ('61000000-0000-0000-0000-000000000001', '66000000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000001', '{"selected_option":"B"}'::jsonb, false, pg_catalog.now() - INTERVAL '36 hours'),
    ('61000000-0000-0000-0000-000000000001', '66000000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000002', '{"selected_option":"A"}'::jsonb, true, pg_catalog.now() - INTERVAL '36 hours'),
    ('61000000-0000-0000-0000-000000000001', '66000000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000003', '{"selected_option":"A"}'::jsonb, true, pg_catalog.now() - INTERVAL '36 hours');

SELECT extensions.ok((
    SELECT evidence.score BETWEEN 0.66 AND 0.67
    FROM private.learning_progress_evidence('61000000-0000-0000-0000-000000000001', NULL, pg_catalog.now()) AS evidence
    WHERE evidence.evidence_type = 'practice_activity'
    LIMIT 1
), 'the latest repeated answer updates one completed activity score without adding a unit') LIMIT 1;

SELECT extensions.is(
    private.learning_recency_weight(pg_catalog.now() - INTERVAL '90 days', pg_catalog.now()),
    0.5::numeric,
    '90-day recency half-life halves an evidence weight'
) LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(4, 2, pg_catalog.now(), pg_catalog.now(), 0.99), 'insufficient_evidence'::text, 'one high score cannot overcome fewer than five evidence units') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 1, pg_catalog.now(), pg_catalog.now(), 0.99), 'insufficient_evidence'::text, 'evidence from one date is not enough') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 2, pg_catalog.now(), pg_catalog.now(), 0.599), 'emerging'::text, 'accuracy below sixty percent is emerging') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 2, pg_catalog.now(), pg_catalog.now(), 0.60), 'developing'::text, 'sixty percent is the developing boundary') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 2, pg_catalog.now(), pg_catalog.now(), 0.799), 'developing'::text, 'accuracy below eighty percent remains developing') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 2, pg_catalog.now(), pg_catalog.now(), 0.80), 'secure'::text, 'eighty percent is the secure boundary') LIMIT 1;
SELECT extensions.is(private.learning_mastery_status(5, 2, pg_catalog.now() - INTERVAL '91 days', pg_catalog.now(), 1.0), 'insufficient_evidence'::text, 'stale evidence is not treated as mastery') LIMIT 1;
SELECT extensions.has_column('public', 'progress_records', 'calculation_version', 'progress snapshots store their model version') LIMIT 1;
SELECT extensions.has_column('public', 'progress_records', 'source_event_id', 'each snapshot retains its triggering source event') LIMIT 1;
SELECT extensions.ok(NOT has_function_privilege('anon', 'public.get_student_progress_overview()', 'EXECUTE'), 'anonymous callers cannot execute student progress APIs') LIMIT 1;
SELECT extensions.ok(has_function_privilege('authenticated', 'public.get_student_progress_overview()', 'EXECUTE'), 'authenticated callers can execute the scoped student overview') LIMIT 1;
SELECT extensions.ok(NOT has_function_privilege('authenticated', 'private.calculate_student_progress(uuid,timestamp with time zone)', 'EXECUTE'), 'browser clients cannot execute internal progress aggregators') LIMIT 1;
SELECT extensions.ok(NOT has_table_privilege('authenticated', 'public.progress_records', 'INSERT'), 'browser clients cannot forge progress snapshots') LIMIT 1;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is((public.get_student_progress_overview()->>'calculation_version'), 'mastery-v1'::text, 'student overview identifies the active calculation version') LIMIT 1;
SELECT extensions.is((public.get_student_topic_mastery((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1))->'mastery'->>'status'), 'developing'::text, 'topic-level status reflects weighted graded and completed-practice evidence') LIMIT 1;
SELECT extensions.is((public.get_student_topic_mastery((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1))->'mastery'->>'completed_practice_activities')::integer, 1, 'a completed practice activity counts once despite a repeated item response') LIMIT 1;
SELECT extensions.is((SELECT objective.value->>'status'
    FROM pg_catalog.jsonb_array_elements(public.get_student_topic_mastery((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1))->'objectives') AS objective(value)
    WHERE objective.value->>'learning_objective' = 'discriminant_nature' LIMIT 1),
    'insufficient_evidence'::text, 'a single objective response remains insufficient') LIMIT 1;
SELECT extensions.is((public.get_student_assessment_history(20)->>'total_attempts')::integer, 4, 'assessment history preserves all repeated attempts') LIMIT 1;
SELECT extensions.is((SELECT activity.value->>'status'
    FROM pg_catalog.jsonb_array_elements(public.get_student_recent_learning_activity(20)->'activity') AS activity(value)
    WHERE activity.value->>'activity_type' = 'practice' LIMIT 1),
    'completed'::text, 'recent activity distinguishes a fully answered practice activity') LIMIT 1;
SELECT extensions.is((SELECT (activity.value->>'completed_items')::integer
    FROM pg_catalog.jsonb_array_elements(public.get_student_recent_learning_activity(20)->'activity') AS activity(value)
    WHERE activity.value->>'activity_type' = 'practice' LIMIT 1),
    3, 'recent activity records the real completed item count') LIMIT 1;
SELECT extensions.ok((SELECT (comparison.value->>'comparable')::boolean
    FROM pg_catalog.jsonb_array_elements(public.get_student_progress_comparison(30)->'comparisons') AS comparison(value)
    WHERE comparison.value->>'is_topic_level' = 'true' LIMIT 1), 'topic comparison is available only after evidence in both periods') LIMIT 1;
SELECT extensions.ok((SELECT (comparison.value->>'comparable')::boolean
    FROM pg_catalog.jsonb_array_elements(public.get_student_progress_comparison(30)->'comparisons') AS comparison(value)
    WHERE comparison.value->>'learning_objective' = 'factorisation_roots' LIMIT 1), 'objective comparison is computed from actual dated records') LIMIT 1;
SELECT extensions.ok(NOT (SELECT (comparison.value->>'comparable')::boolean
    FROM pg_catalog.jsonb_array_elements(public.get_student_progress_comparison(30)->'comparisons') AS comparison(value)
    WHERE comparison.value->>'learning_objective' = 'discriminant_nature' LIMIT 1), 'a one-item objective is not compared as mastery') LIMIT 1;
SELECT extensions.ok((SELECT (public.get_student_mastery_history((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), NULL, 50)->'observations') IS NOT NULL), 'student mastery history returns an observation list') LIMIT 1;
SELECT extensions.ok((SELECT pg_catalog.count(*) >= 5
    FROM pg_catalog.jsonb_array_elements(public.get_student_mastery_history((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), NULL, 50)->'observations')), 'assessment and practice events produce persistent dated snapshots') LIMIT 1;
SELECT extensions.ok((SELECT pg_catalog.bool_and(record.calculation_version = 'mastery-v1')
    FROM public.progress_records AS record
    WHERE record.student_id = '61000000-0000-0000-0000-000000000001'), 'all new historical snapshots retain the v1 calculation identifier') LIMIT 1;
RESET ROLE;

INSERT INTO public.progress_records (
    class_id, student_id, topic_id, mastery_score, evidence_count, basis,
    learning_objective, is_topic_summary, calculation_version, mastery_status,
    evidence_through, evidence_summary
) VALUES (
    NULL, '61000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1),
    0.5000, 5, 'combined', 'topic_overall', true, 'mastery-v2', 'developing',
    pg_catalog.now(), '{}'::jsonb
);
SELECT extensions.is((SELECT pg_catalog.count(*)::integer FROM public.progress_records WHERE calculation_version = 'mastery-v2'), 1, 'a changed calculation can be stored under a new version without overwriting v1') LIMIT 1;
SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.ok(
    (public.get_student_mastery_history((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), NULL, 50)->>'calculation_version' = 'mastery-v1')
    AND (SELECT pg_catalog.bool_and(observation.value->>'calculation_version' = 'mastery-v1')
         FROM pg_catalog.jsonb_array_elements(public.get_student_mastery_history((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), NULL, 50)->'observations') AS observation(value)),
    'history API keeps calculations explicitly versioned and does not silently mix semantics'
) LIMIT 1;
RESET ROLE;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000002', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is((public.get_student_progress_overview()->'topics'->0->>'status'), 'insufficient_evidence'::text, 'a learner with no evidence gets an explicit insufficient-evidence topic state') LIMIT 1;
SELECT extensions.is((public.get_student_topic_mastery((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1))->'mastery'->>'mastery_percent'), NULL::text, 'missing evidence is represented by a null estimate rather than zero') LIMIT 1;
SELECT extensions.is((public.get_student_assessment_history(20)->>'total_attempts')::integer, 0, 'another student receives only their own empty attempt history') LIMIT 1;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.get_student_mastery_history((SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1), NULL, 50)->'observations'), 0, 'another student cannot retrieve the first learner progress snapshots') LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*)::integer FROM public.progress_records), 0, 'RLS hides all other learner snapshots from this student') LIMIT 1;
RESET ROLE;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000010', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is((public.get_class_learning_progress('62000000-0000-0000-0000-000000000001')->>'active_students')::integer, 1, 'owning teacher receives only the active class roster count') LIMIT 1;
SELECT extensions.is((public.get_class_learning_progress('62000000-0000-0000-0000-000000000001')->'topics'->0->>'evidence_units')::integer, 13, 'class summary pools only the owning class assessment and completed-practice evidence') LIMIT 1;
SELECT extensions.ok(NOT ((public.get_class_learning_progress('62000000-0000-0000-0000-000000000001')->'topics'->0) ? 'student_id'), 'class aggregates omit individual student identifiers') LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*)::integer FROM public.progress_records), 0, 'class owners do not read learner-only snapshots directly') LIMIT 1;
RESET ROLE;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000011', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok(
    $$SELECT public.get_class_learning_progress('62000000-0000-0000-0000-000000000001')$$,
    '42501', NULL, 'a different teacher cannot access another teacher class summary'
) LIMIT 1;
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;
