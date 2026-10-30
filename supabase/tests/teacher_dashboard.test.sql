-- Run with: supabase db reset && supabase test db
-- Transaction-scoped synthetic fixture; all users and learning records are rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(28) LIMIT 1;

INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
) VALUES
    ('61000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'td-student-a@test.invalid', '', '{}', '{"display_name":"Learner A"}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'td-student-b@test.invalid', '', '{}', '{"display_name":"Learner B"}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'td-student-c@test.invalid', '', '{}', '{"display_name":"Learner C"}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'td-teacher-a@test.invalid', '', '{}', '{"display_name":"Teacher A"}', pg_catalog.now(), pg_catalog.now()),
    ('61000000-0000-4000-8000-000000000011', 'authenticated', 'authenticated', 'td-teacher-b@test.invalid', '', '{}', '{"display_name":"Teacher B"}', pg_catalog.now(), pg_catalog.now());

UPDATE public.profiles SET app_role = 'teacher'
WHERE user_id IN ('61000000-0000-4000-8000-000000000010', '61000000-0000-4000-8000-000000000011');

INSERT INTO public.classes (id, teacher_id, name, grade_level, subject) VALUES
    ('62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000010', 'Dashboard Class A', 10, 'Mathematics'),
    ('62000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000011', 'Dashboard Class B', 10, 'Mathematics'),
    ('62000000-0000-4000-8000-000000000003', '61000000-0000-4000-8000-000000000010', 'Dashboard Empty Class', 10, 'Mathematics');

INSERT INTO public.questions (id, author_teacher_id, topic_id, question_type, prompt, options)
SELECT q.id, q.teacher_id, t.id, 'single_choice', q.prompt,
       '[{"id":"a","text":"Incorrect"},{"id":"b","text":"Correct"}]'::jsonb
FROM (VALUES
    ('63000000-0000-4000-8000-000000000001'::uuid, '61000000-0000-4000-8000-000000000010'::uuid, 'Stage 6 item one'),
    ('63000000-0000-4000-8000-000000000002'::uuid, '61000000-0000-4000-8000-000000000010'::uuid, 'Stage 6 item two'),
    ('63000000-0000-4000-8000-000000000003'::uuid, '61000000-0000-4000-8000-000000000011'::uuid, 'Stage 6 item other class')
) AS q(id, teacher_id, prompt)
CROSS JOIN LATERAL (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1) AS t;

INSERT INTO public.question_answer_keys (question_id, answer_config) VALUES
    ('63000000-0000-4000-8000-000000000001', '{"correct_option":"b"}'),
    ('63000000-0000-4000-8000-000000000002', '{"correct_option":"b"}'),
    ('63000000-0000-4000-8000-000000000003', '{"correct_option":"b"}');
INSERT INTO public.question_guidance (question_id, explanation, misconception_tags) VALUES
    ('63000000-0000-4000-8000-000000000001', 'Reviewed explanation one.', ARRAY[]::text[]),
    ('63000000-0000-4000-8000-000000000002', 'Reviewed explanation two.', ARRAY[]::text[]),
    ('63000000-0000-4000-8000-000000000003', 'Reviewed explanation three.', ARRAY[]::text[]);

INSERT INTO public.assessments (id, class_id, created_by_teacher_id, title, assessment_type, status) VALUES
    ('64000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000010', 'Dashboard Assessment 1', 'diagnostic', 'published'),
    ('64000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000010', 'Dashboard Assessment 2', 'practice', 'published'),
    ('64000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000011', 'Other Class Assessment', 'diagnostic', 'published');
INSERT INTO public.assessment_questions (assessment_id, question_id, position, points) VALUES
    ('64000000-0000-4000-8000-000000000001', '63000000-0000-4000-8000-000000000001', 1, 1),
    ('64000000-0000-4000-8000-000000000002', '63000000-0000-4000-8000-000000000002', 1, 1),
    ('64000000-0000-4000-8000-000000000003', '63000000-0000-4000-8000-000000000003', 1, 1);
INSERT INTO public.enrollments (class_id, student_id, status) VALUES
    ('62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', 'active'),
    ('62000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', 'active'),
    ('62000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000003', 'active');

INSERT INTO public.assessment_attempts (id, assessment_id, student_id, attempt_number, status, submitted_at, score_percent) VALUES
    ('65000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', 1, 'graded', pg_catalog.now(), 0),
    ('65000000-0000-4000-8000-000000000002', '64000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', 1, 'graded', pg_catalog.now(), 100),
    ('65000000-0000-4000-8000-000000000003', '64000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', 2, 'in_progress', NULL, NULL),
    ('65000000-0000-4000-8000-000000000004', '64000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000001', 1, 'graded', pg_catalog.now(), 0),
    ('65000000-0000-4000-8000-000000000005', '64000000-0000-4000-8000-000000000003', '61000000-0000-4000-8000-000000000003', 1, 'graded', pg_catalog.now(), 100);
INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer, is_answered, score_percent, is_correct, points_earned, graded_at) VALUES
    ('65000000-0000-4000-8000-000000000001', '64000000-0000-4000-8000-000000000001', '63000000-0000-4000-8000-000000000001', '{"selected_option":"a"}', true, 0, false, 0, pg_catalog.now()),
    ('65000000-0000-4000-8000-000000000002', '64000000-0000-4000-8000-000000000001', '63000000-0000-4000-8000-000000000001', '{"selected_option":"b"}', true, 100, true, 1, pg_catalog.now()),
    ('65000000-0000-4000-8000-000000000004', '64000000-0000-4000-8000-000000000002', '63000000-0000-4000-8000-000000000002', '{"selected_option":"a"}', true, 0, false, 0, pg_catalog.now()),
    ('65000000-0000-4000-8000-000000000005', '64000000-0000-4000-8000-000000000003', '63000000-0000-4000-8000-000000000003', '{"selected_option":"b"}', true, 100, true, 1, pg_catalog.now());

-- Use the common diagnosis columns so the fixture works with both the original and
-- versioned Stage 3 schemas. Its meaning is deliberately candidate-only.
DO $$
DECLARE
    v_topic_id uuid;
BEGIN
    SELECT id INTO v_topic_id FROM public.topics WHERE code = 'quadratic-equations';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnoses' AND column_name = 'student_id') THEN
        EXECUTE 'INSERT INTO public.diagnoses (source_attempt_id, topic_id, misconception_code, summary, evidence, confidence, student_id) VALUES ($1, $2, $3, $4, $5, $6, $7)'
        USING '65000000-0000-4000-8000-000000000001'::uuid, v_topic_id, 'factor_pair_error',
              'Possible factor-pair pattern; reasoning was not captured.',
              '{"interpretation":"candidate_not_confirmed","observed_pattern":"fixture signal"}'::jsonb,
              0.64, '61000000-0000-4000-8000-000000000001'::uuid;
    ELSE
        INSERT INTO public.diagnoses (source_attempt_id, topic_id, misconception_code, summary, evidence, confidence)
        VALUES ('65000000-0000-4000-8000-000000000001', v_topic_id, 'factor_pair_error',
                'Possible factor-pair pattern; reasoning was not captured.',
                '{"interpretation":"candidate_not_confirmed","observed_pattern":"fixture signal"}'::jsonb, 0.64);
    END IF;
END;
$$;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000010', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.list_teacher_classes()), 2, 'teacher class list contains only two owned classes') LIMIT 1;
SELECT extensions.ok(NOT (public.list_teacher_classes()::text LIKE '%Dashboard Class B%'), 'teacher class list does not reveal another teacher class') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')->'class'->>'active_enrollment_count')::bigint, 2::bigint, 'class overview counts active enrollments') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')->'class_performance'->>'learner_assessment_observations')::bigint, 3::bigint, 'class performance counts latest graded learner-assessment observations') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')->'class_performance'->>'mean_latest_graded_score_percent')::numeric, 33.3::numeric, 'class performance average uses latest graded attempt per assessment and excludes incomplete attempts') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_analytics('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'analytics'->>'participating_student_count')::bigint, 2::bigint, 'assessment participation counts distinct active learners') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_analytics('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'analytics'->>'participation_rate_percent')::numeric, 100.0::numeric, 'participation denominator is the two active enrollments') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_analytics('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'analytics'->>'mean_latest_graded_score_percent')::numeric, 50.0::numeric, 'score average excludes an in-progress retake') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_analytics('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'analytics'->>'unfinished_attempt_count')::bigint, 1::bigint, 'in-progress attempt is separately counted as unfinished') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')->'topic_mastery_distribution'->0->'mastery_bands'->>'below_40_further_practice')::bigint, 1::bigint, 'topic distribution counts one learner below 40 percent') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')->'topic_mastery_distribution'->0->'mastery_bands'->>'70_or_above_secure_for_now')::bigint, 1::bigint, 'topic distribution counts one learner at or above 70 percent') LIMIT 1;
SELECT extensions.is((public.get_teacher_misconception_heatmap('62000000-0000-4000-8000-000000000001')->'cells'->0->>'interpretation'), 'possible_pattern_not_confirmed'::text, 'heatmap exposes candidate evidence as uncertain rather than confirmed') LIMIT 1;
SELECT extensions.is((public.get_teacher_misconception_heatmap('62000000-0000-4000-8000-000000000001')->'cells'->0->>'eligible_graded_attempt_count')::bigint, 3::bigint, 'heatmap denominator includes only latest graded topic-eligible attempts in this class') LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*) FROM jsonb_array_elements(public.get_teacher_students_needing_support('62000000-0000-4000-8000-000000000001')->'students_for_review') AS s WHERE s.value->>'student_id' = '61000000-0000-4000-8000-000000000001'), 1::bigint, 'repeated low latest-graded scores place the learner in a supportive review list') LIMIT 1;
SELECT extensions.ok((SELECT s.value->'criteria_met' ? 'same_topic_incorrect_responses_across_at_least_two_graded_assessments' FROM jsonb_array_elements(public.get_teacher_students_needing_support('62000000-0000-4000-8000-000000000001')->'students_for_review') AS s WHERE s.value->>'student_id' = '61000000-0000-4000-8000-000000000001'), 'repeated wrong responses are counted only across distinct graded assessments') LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*) FROM jsonb_array_elements(public.get_teacher_students_needing_support('62000000-0000-4000-8000-000000000001')->'insufficient_evidence') AS s WHERE s.value->>'student_id' = '61000000-0000-4000-8000-000000000002'), 1::bigint, 'one graded assessment is reported as insufficient evidence, not a negative label') LIMIT 1;
SELECT extensions.is((public.get_teacher_student_learning_detail('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001')->>'attempt_history_total_count')::bigint, 3::bigint, 'authorized student detail returns persisted graded and incomplete attempt history') LIMIT 1;
SELECT extensions.is((public.get_teacher_student_learning_detail('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001')->'candidate_signals'->0->>'interpretation'), 'possible_pattern_not_confirmed'::text, 'student detail retains uncertainty labeling') LIMIT 1;
SELECT extensions.ok(pg_catalog.jsonb_array_length(public.get_teacher_teaching_recommendations('62000000-0000-4000-8000-000000000001')->'recommendations') > 0, 'teaching recommendation is generated from class topic evidence') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_report_data('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'export_safety'->>'contains_student_identifiers'), 'false'::text, 'assessment report is aggregate-only and omits student identifiers') LIMIT 1;
SELECT extensions.is((public.get_teacher_assessment_report_data('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001')->'export_safety'->>'contains_answer_keys'), 'false'::text, 'assessment report omits answer keys') LIMIT 1;
SELECT extensions.throws_ok($$SELECT public.get_teacher_class_overview('62000000-0000-4000-8000-000000000002')$$, '42501', NULL, 'teacher cannot access another teacher class overview') LIMIT 1;
SELECT extensions.throws_ok($$SELECT public.get_teacher_assessment_analytics('62000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000003')$$, '42501', NULL, 'teacher cannot query an assessment from another class') LIMIT 1;
SELECT extensions.throws_ok($$SELECT public.get_teacher_student_learning_detail('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000003')$$, '42501', NULL, 'teacher cannot drill down into a student outside the class') LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*) FROM public.assessment_attempts), 4::bigint, 'existing RLS limits direct attempt reads to assessments in owned classes') LIMIT 1;
SELECT extensions.is((public.get_teacher_class_overview('62000000-0000-4000-8000-000000000003')->'class'->>'active_enrollment_count')::bigint, 0::bigint, 'empty class overview returns a zero active roster') LIMIT 1;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.get_teacher_class_overview('62000000-0000-4000-8000-000000000003')->'topic_mastery_distribution'), 0, 'empty class has no fabricated topic mastery evidence') LIMIT 1;
RESET ROLE;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000001', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_teacher_class_overview('62000000-0000-4000-8000-000000000001')$$, '42501', NULL, 'student role cannot call a teacher dashboard endpoint') LIMIT 1;
RESET ROLE;

SELECT * FROM extensions.finish() LIMIT 1;
ROLLBACK;
