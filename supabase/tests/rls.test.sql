-- Run locally with: supabase db reset && supabase test db
-- This fixture is transaction-scoped and rolls back all Auth users and records.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(57) LIMIT 1;

-- Stable synthetic identities are safe because all fixture writes roll back.
INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'student-a@test.invalid', '', '{}', '{"display_name":"Student A","role":"teacher","app_role":"teacher"}', pg_catalog.now(), pg_catalog.now()),
    ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'student-b@test.invalid', '', '{}', '{"display_name":"Student B"}', pg_catalog.now(), pg_catalog.now()),
    ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'student-c@test.invalid', '', '{}', '{"display_name":"Student C"}', pg_catalog.now(), pg_catalog.now()),
    ('10000000-0000-0000-0000-000000000010', 'authenticated', 'authenticated', 'teacher-a@test.invalid', '', '{}', '{"display_name":"Teacher A"}', pg_catalog.now(), pg_catalog.now()),
    ('10000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'teacher-b@test.invalid', '', '{}', '{"display_name":"Teacher B"}', pg_catalog.now(), pg_catalog.now());

UPDATE public.profiles SET app_role = 'teacher'
WHERE user_id IN ('10000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000011');

INSERT INTO public.classes (id, teacher_id, name, grade_level, subject) VALUES
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000010', 'Fixture Class A', 10, 'Mathematics'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000011', 'Fixture Class B', 10, 'Mathematics');

SELECT extensions.is(
    (SELECT p.app_role FROM public.profiles AS p WHERE p.user_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
    'student'::text,
    'Auth trigger provisions student even when user metadata claims teacher'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1),
    1::bigint,
    'initial published Quadratic Equations topic exists'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$INSERT INTO public.topics (subject, grade_level, code, title, is_published)
      VALUES ('Mathematics', 10, 'quadratic-equations', 'Duplicate topic', true)$$,
    '23505', NULL, 'topic subject/grade/code uniqueness is enforced'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$INSERT INTO public.classes (teacher_id, name, grade_level, subject)
      VALUES ('10000000-0000-0000-0000-000000000010', 'Invalid grade', 13, 'Mathematics')$$,
    '23514', NULL, 'class grade constraint rejects values outside 1-12'
) LIMIT 1;

-- Teacher A can create classes only through the identity-bound RPC.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000010', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.lives_ok(
    $$SELECT public.create_class('RPC-owned class', 10::smallint, 'Mathematics', NULL) LIMIT 1$$,
    'trusted teacher can create a class through the scoped function'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.classes WHERE name = 'RPC-owned class' AND teacher_id = '10000000-0000-0000-0000-000000000010' LIMIT 1),
    1::bigint,
    'class owner is derived from the authenticated teacher'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$SELECT public.enroll_student('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001') LIMIT 1$$,
    'class owner can enroll a student'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$SELECT public.enroll_student('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002') LIMIT 1$$,
    'class owner can enroll another student'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.questions (id, author_teacher_id, topic_id, question_type, prompt, options)
      VALUES ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000010',
        (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1),
        'single_choice', 'Which expression is a quadratic equation?', '[{"id":"a","text":"x + 1 = 0"},{"id":"b","text":"x^2 + 1 = 0"}]'::jsonb)$$,
    'teacher can create own question content'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.question_answer_keys (question_id, answer_config, rationale)
      VALUES ('30000000-0000-0000-0000-000000000001', '{"correct_option":"b"}'::jsonb, 'The highest power is two.')$$,
    'question author can store a separate private answer key'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.assessments (id, class_id, created_by_teacher_id, title, assessment_type)
      VALUES ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000010', 'Quadratics Diagnostic A', 'diagnostic')$$,
    'teacher can create a draft assessment for an owned class'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.assessment_questions (assessment_id, question_id, position, points)
      VALUES ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 1, 1)$$,
    'teacher can attach own question to an owned draft assessment'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$UPDATE public.assessments SET status = 'published' WHERE id = '40000000-0000-0000-0000-000000000001'$$,
    'teacher can publish an unstarted draft assessment'
) LIMIT 1;
RESET ROLE;

-- Teacher B has a separate class, assessment, and student.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000011', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.lives_ok(
    $$SELECT public.enroll_student('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003') LIMIT 1$$,
    'second teacher can enroll a student only in the second teacher own class'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.questions (id, author_teacher_id, topic_id, question_type, prompt, options)
      VALUES ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000011',
        (SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1),
        'numeric', 'Solve x^2 - 4 = 0 for the positive root.', '[]'::jsonb)$$,
    'second teacher can create an authored question'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.question_answer_keys (question_id, answer_config)
      VALUES ('30000000-0000-0000-0000-000000000002', '{"value":2}'::jsonb)$$,
    'second teacher can store its own answer key'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.assessments (id, class_id, created_by_teacher_id, title, assessment_type)
      VALUES ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000011', 'Quadratics Diagnostic B', 'diagnostic')$$,
    'second teacher can create an assessment for the second class'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$INSERT INTO public.assessment_questions (assessment_id, question_id, position, points)
      VALUES ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 1, 1)$$,
    'second teacher can attach an authored question'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$UPDATE public.assessments SET status = 'published' WHERE id = '40000000-0000-0000-0000-000000000002'$$,
    'second teacher can publish an unstarted draft assessment'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$SELECT public.enroll_student('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001') LIMIT 1$$,
    '42501', NULL, 'teacher cannot enroll students in a class owned by another teacher'
) LIMIT 1;
RESET ROLE;

-- Student A receives only own data and may participate only in the assigned assessment.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.profiles LIMIT 1),
    1::bigint,
    'student sees only their own profile'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$UPDATE public.profiles SET app_role = 'teacher' WHERE user_id = '10000000-0000-0000-0000-000000000001'$$,
    '42501', NULL, 'student cannot promote self by changing profile role'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.classes LIMIT 1),
    1::bigint,
    'student sees only the enrolled class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.enrollments WHERE student_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read own enrollment'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.enrollments WHERE student_id <> '10000000-0000-0000-0000-000000000001' LIMIT 1),
    0::bigint,
    'student cannot read another student enrollment'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.assessments WHERE id = '40000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read published assessment assigned to own class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.assessments WHERE id = '40000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'student cannot read assessment in another class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.question_answer_keys LIMIT 1),
    0::bigint,
    'student cannot read any answer key'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$SELECT public.start_assessment('40000000-0000-0000-0000-000000000001') LIMIT 1$$,
    'enrolled student can start assigned published assessment'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.assessment_attempts WHERE assessment_id = '40000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read own newly created attempt'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$SELECT public.start_assessment('40000000-0000-0000-0000-000000000002') LIMIT 1$$,
    '42501', NULL, 'student cannot start an assessment for a class they do not attend'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$INSERT INTO public.classes (teacher_id, name, grade_level, subject)
      VALUES ('10000000-0000-0000-0000-000000000001', 'Student-owned class', 10, 'Mathematics')$$,
    '42501', NULL, 'student cannot insert a class or assign ownership'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$INSERT INTO public.enrollments (class_id, student_id)
      VALUES ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001')$$,
    '42501', NULL, 'student cannot self-enroll through direct table access'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer)
      VALUES ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001', '{"value":"b"}'::jsonb)$$,
    '42501', NULL, 'student cannot directly insert or forge a scored response'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$SELECT public.save_response(
        (SELECT aa.id FROM public.assessment_attempts AS aa
         WHERE aa.assessment_id = '40000000-0000-0000-0000-000000000001'
           AND aa.student_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
        '30000000-0000-0000-0000-000000000001', '{"selected_option":"b"}'::jsonb
    ) LIMIT 1$$,
    'student can save an answer only for own active attempt and assigned question'
) LIMIT 1;
SELECT extensions.lives_ok(
    $$UPDATE public.profiles SET display_name = 'Student A Updated'
      WHERE user_id = '10000000-0000-0000-0000-000000000001'$$,
    'student can update own display name'
) LIMIT 1;
RESET ROLE;

-- Create synthetic report records as the privileged test runner. These inserts
-- are rolled back at the end and intentionally model trusted server-side writes.
INSERT INTO public.assessment_attempts (
    id, assessment_id, student_id, attempt_number, status, submitted_at
) VALUES
    ('50000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 1, 'submitted', pg_catalog.now()),
    ('50000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 1, 'submitted', pg_catalog.now());

INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer, score_percent, is_correct, graded_at)
VALUES
    ('50000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '{"selected_option":"b"}'::jsonb, 100, true, pg_catalog.now()),
    ('50000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', '{"value":2}'::jsonb, 100, true, pg_catalog.now());

INSERT INTO public.diagnoses (source_attempt_id, topic_id, misconception_code, summary, evidence, confidence)
SELECT aa.id, q.topic_id, 'sign_error', 'Synthetic diagnosis for RLS test', '{"source":"synthetic"}'::jsonb, 0.900
FROM public.assessment_attempts AS aa
JOIN public.assessments AS a ON a.id = aa.assessment_id
JOIN public.assessment_questions AS aq ON aq.assessment_id = a.id
JOIN public.questions AS q ON q.id = aq.question_id
WHERE aa.id IN ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000003')
LIMIT 2;

INSERT INTO public.diagnoses (source_attempt_id, topic_id, misconception_code, summary, evidence, confidence)
SELECT aa.id, q.topic_id, 'coefficient_confusion', 'Synthetic diagnosis for own attempt', '{"source":"synthetic"}'::jsonb, 0.850
FROM public.assessment_attempts AS aa
JOIN public.assessment_questions AS aq ON aq.assessment_id = aa.assessment_id
JOIN public.questions AS q ON q.id = aq.question_id
WHERE aa.assessment_id = '40000000-0000-0000-0000-000000000001'
  AND aa.student_id = '10000000-0000-0000-0000-000000000001'
LIMIT 1;

INSERT INTO public.learning_sessions (class_id, student_id, topic_id, activity_type, details)
SELECT x.class_id, x.student_id, t.id, 'practice', '{"source":"synthetic"}'::jsonb
FROM (VALUES
    ('20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000001'::uuid),
    ('20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000002'::uuid),
    ('20000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000003'::uuid)
) AS x(class_id, student_id)
CROSS JOIN LATERAL (
    SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1
) AS t
LIMIT 3;

INSERT INTO public.progress_records (class_id, student_id, topic_id, mastery_score, evidence_count, basis)
SELECT e.class_id, e.student_id, t.id, 0.6500, 2, 'assessment'
FROM public.enrollments AS e
CROSS JOIN LATERAL (
    SELECT id FROM public.topics WHERE code = 'quadratic-equations' LIMIT 1
) AS t
WHERE e.student_id IN (
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003'
)
LIMIT 3;

-- Student A cannot see Student B's private report records, but can see own.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.responses WHERE attempt_id = '50000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'student cannot read another student response'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.diagnoses WHERE source_attempt_id = '50000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'student cannot read another student diagnosis'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.learning_sessions WHERE student_id = '10000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'student cannot read another student session history'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records WHERE student_id = '10000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'student cannot read another student progress report'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.diagnoses AS d
     JOIN public.assessment_attempts AS aa ON aa.id = d.source_attempt_id
     WHERE aa.student_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read own diagnosis evidence'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.learning_sessions WHERE student_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read own learning sessions'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records WHERE student_id = '10000000-0000-0000-0000-000000000001' LIMIT 1),
    1::bigint,
    'student can read own dated progress'
) LIMIT 1;
RESET ROLE;

-- Teacher A sees enrolled learners' records but not Teacher B's class data.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000010', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.profiles WHERE app_role = 'student' LIMIT 1),
    2::bigint,
    'teacher can read profiles only for students enrolled in owned classes'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.responses LIMIT 1),
    2::bigint,
    'teacher can read response records for the owned class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.diagnoses LIMIT 1),
    2::bigint,
    'teacher can read diagnosis records for the owned class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records LIMIT 1),
    2::bigint,
    'teacher can read progress records for the owned class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.profiles WHERE user_id = '10000000-0000-0000-0000-000000000003' LIMIT 1),
    0::bigint,
    'teacher cannot read a student profile enrolled only in another class'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.responses WHERE attempt_id = '50000000-0000-0000-0000-000000000003' LIMIT 1),
    0::bigint,
    'teacher cannot read response data for another teacher class'
) LIMIT 1;
RESET ROLE;

-- Student B can read their own reports, while Teacher B cannot read Teacher A's.
SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.responses WHERE attempt_id = '50000000-0000-0000-0000-000000000002' LIMIT 1),
    1::bigint,
    'second student can read own response report'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.diagnoses WHERE source_attempt_id = '50000000-0000-0000-0000-000000000002' LIMIT 1),
    1::bigint,
    'second student can read own diagnosis'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.learning_sessions WHERE student_id = '10000000-0000-0000-0000-000000000002' LIMIT 1),
    1::bigint,
    'second student can read own session history'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records WHERE student_id = '10000000-0000-0000-0000-000000000002' LIMIT 1),
    1::bigint,
    'second student can read own progress report'
) LIMIT 1;
RESET ROLE;

SELECT pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000011', true) LIMIT 1;
SET LOCAL ROLE authenticated;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records LIMIT 1),
    1::bigint,
    'second teacher can read its own class progress'
) LIMIT 1;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.progress_records WHERE student_id = '10000000-0000-0000-0000-000000000002' LIMIT 1),
    0::bigint,
    'second teacher cannot read another teacher class progress'
) LIMIT 1;
RESET ROLE;

-- Only explicitly published topic metadata is available to signed-out clients.
SET LOCAL ROLE anon;
SELECT extensions.is(
    (SELECT pg_catalog.count(*) FROM public.topics LIMIT 1),
    1::bigint,
    'anonymous client can read published topic metadata'
) LIMIT 1;
SELECT extensions.throws_ok(
    $$SELECT id FROM public.classes LIMIT 1$$,
    '42501', NULL, 'anonymous client cannot query classroom data'
) LIMIT 1;
RESET ROLE;

SELECT * FROM extensions.finish() LIMIT 100;
ROLLBACK;
