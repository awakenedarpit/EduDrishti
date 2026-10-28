-- Stage 3 diagnosis rules and authorization. Run with `supabase test db`.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(6) LIMIT 1;

INSERT INTO auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
('51000000-0000-0000-0000-000000000001','authenticated','authenticated','stage3-student@test.invalid','','{}','{}',pg_catalog.now(),pg_catalog.now()),
('51000000-0000-0000-0000-000000000002','authenticated','authenticated','stage3-other@test.invalid','','{}','{}',pg_catalog.now(),pg_catalog.now()),
('51000000-0000-0000-0000-000000000010','authenticated','authenticated','stage3-teacher@test.invalid','','{}','{}',pg_catalog.now(),pg_catalog.now()),
('51000000-0000-0000-0000-000000000011','authenticated','authenticated','stage3-outsider@test.invalid','','{}','{}',pg_catalog.now(),pg_catalog.now());
UPDATE public.profiles SET app_role='teacher' WHERE user_id IN ('51000000-0000-0000-0000-000000000010','51000000-0000-0000-0000-000000000011');
INSERT INTO public.classes (id, teacher_id, name, grade_level, subject) VALUES
('52000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000010','Stage 3 test class',10,'Mathematics');
INSERT INTO public.enrollments (class_id, student_id, created_by_teacher_id) VALUES
('52000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000010');
INSERT INTO public.questions (id, author_teacher_id, topic_id, question_type, prompt, options) VALUES
('53000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000010',(SELECT id FROM public.topics WHERE code='quadratic-equations' LIMIT 1),'single_choice','Solve x²−5x+6=0.', '[{"id":"A","text":"1 and 6"},{"id":"B","text":"2 and 3"}]'::jsonb),
('53000000-0000-0000-0000-000000000002','51000000-0000-0000-0000-000000000010',(SELECT id FROM public.topics WHERE code='quadratic-equations' LIMIT 1),'single_choice','What is the root pair?', '[{"id":"A","text":"1 and 6"},{"id":"B","text":"2 and 3"}]'::jsonb);
INSERT INTO public.question_answer_keys (question_id, answer_config) VALUES
('53000000-0000-0000-0000-000000000001','{"correct_option":"B"}'::jsonb),
('53000000-0000-0000-0000-000000000002','{"correct_option":"B"}'::jsonb);
INSERT INTO public.question_guidance (question_id, explanation, misconception_tags) VALUES
('53000000-0000-0000-0000-000000000001','The factor pair must sum to −5 and multiply to 6.',ARRAY['factor_pair_error']),
('53000000-0000-0000-0000-000000000002','The factor pair must sum to −5 and multiply to 6.',ARRAY['factor_pair_error']);
INSERT INTO public.assessments (id,class_id,created_by_teacher_id,title,assessment_type,status) VALUES
('54000000-0000-0000-0000-000000000001','52000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000010','Stage 3 matched rule','diagnostic','published'),
('54000000-0000-0000-0000-000000000002','52000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000010','Stage 3 unmatched answer','diagnostic','published');
INSERT INTO public.assessment_questions (assessment_id,question_id,position,points) VALUES
('54000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000001',1,1),
('54000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000002',1,1);
INSERT INTO private.misconception_rules (id,question_id,misconception_code,answer_pattern,summary,explanation,corrective_example,followup_question,confidence) VALUES
('55000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000001','factor_pair_error','{"selected_option":"A"}'::jsonb,'Factor pair mismatch.','Product and sum differ.','Try 2 and 3.','Which pair sums to −7?',0.95);

SELECT pg_catalog.set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true) LIMIT 1;
SELECT public.start_assessment('54000000-0000-0000-0000-000000000001') LIMIT 1;
SELECT public.save_response((SELECT id FROM public.assessment_attempts WHERE student_id='51000000-0000-0000-0000-000000000001' AND assessment_id='54000000-0000-0000-0000-000000000001' LIMIT 1),'53000000-0000-0000-0000-000000000001','{"selected_option":"A"}'::jsonb) LIMIT 1;
SELECT public.complete_assessment((SELECT id FROM public.assessment_attempts WHERE student_id='51000000-0000-0000-0000-000000000001' AND assessment_id='54000000-0000-0000-0000-000000000001' LIMIT 1)) LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*) FROM public.diagnoses WHERE source_attempt_id=(SELECT id FROM public.assessment_attempts WHERE assessment_id='54000000-0000-0000-0000-000000000001' LIMIT 1) LIMIT 1),1::bigint,'a reviewed distractor rule creates exactly one diagnosis') LIMIT 1;
SELECT extensions.ok((SELECT (public.get_student_diagnoses((SELECT id FROM public.assessment_attempts WHERE assessment_id='54000000-0000-0000-0000-000000000001' LIMIT 1))->'diagnoses'->0->>'misconception_code')='factor_pair_error' LIMIT 1),'student receives an evidence-linked diagnosis after grading') LIMIT 1;

SELECT public.start_assessment('54000000-0000-0000-0000-000000000002') LIMIT 1;
SELECT public.save_response((SELECT id FROM public.assessment_attempts WHERE student_id='51000000-0000-0000-0000-000000000001' AND assessment_id='54000000-0000-0000-0000-000000000002' LIMIT 1),'53000000-0000-0000-0000-000000000002','{"selected_option":"A"}'::jsonb) LIMIT 1;
SELECT public.complete_assessment((SELECT id FROM public.assessment_attempts WHERE student_id='51000000-0000-0000-0000-000000000001' AND assessment_id='54000000-0000-0000-0000-000000000002' LIMIT 1)) LIMIT 1;
SELECT extensions.is((SELECT pg_catalog.count(*) FROM public.diagnoses WHERE source_attempt_id=(SELECT id FROM public.assessment_attempts WHERE assessment_id='54000000-0000-0000-0000-000000000002' LIMIT 1) LIMIT 1),0::bigint,'an unmatched incorrect response is left undiagnosed') LIMIT 1;
SELECT extensions.throws_ok($$SELECT public.get_student_diagnoses((SELECT id FROM public.assessment_attempts WHERE assessment_id='54000000-0000-0000-0000-000000000001' LIMIT 1))$$,'42501',NULL,'another student cannot retrieve this learner diagnosis') LIMIT 1;

SELECT pg_catalog.set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000010',true) LIMIT 1;
SELECT extensions.ok((public.get_class_misconception_summary('52000000-0000-0000-0000-000000000001')->'diagnoses'->0->>'affected_students')::integer=1,'owning teacher sees an aggregate without student identity') LIMIT 1;
SELECT pg_catalog.set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000011',true) LIMIT 1;
SELECT extensions.throws_ok($$SELECT public.get_class_misconception_summary('52000000-0000-0000-0000-000000000001')$$,'42501',NULL,'another teacher cannot retrieve the class diagnosis summary') LIMIT 1;

ROLLBACK;
