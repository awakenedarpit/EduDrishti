-- Stage 3: evidence-linked, deterministic misconception diagnosis.
-- Only reviewed answer-pattern rules create a diagnosis. Unmatched wrong answers
-- remain unclassified; a wrong answer alone is not treated as proof of a misconception.
BEGIN;

CREATE TABLE private.misconception_rules (
    id uuid PRIMARY KEY,
    question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    misconception_code text NOT NULL CHECK (misconception_code ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
    answer_pattern jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(answer_pattern) = 'object'),
    summary text NOT NULL CHECK (char_length(pg_catalog.btrim(summary)) BETWEEN 1 AND 1000),
    explanation text NOT NULL CHECK (char_length(pg_catalog.btrim(explanation)) BETWEEN 1 AND 3000),
    corrective_example text NOT NULL CHECK (char_length(pg_catalog.btrim(corrective_example)) BETWEEN 1 AND 3000),
    followup_question text NOT NULL CHECK (char_length(pg_catalog.btrim(followup_question)) BETWEEN 1 AND 2000),
    confidence numeric(4,3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    UNIQUE (question_id, misconception_code, answer_pattern)
);
REVOKE ALL ON TABLE private.misconception_rules FROM PUBLIC, anon, authenticated;

CREATE INDEX misconception_rules_question_active_idx
    ON private.misconception_rules (question_id) WHERE is_active;

-- These rules are deliberately narrow distractor matches; any other response
-- receives ordinary grading feedback but no asserted diagnosis.
INSERT INTO private.misconception_rules (
    id, question_id, misconception_code, answer_pattern, summary,
    explanation, corrective_example, followup_question, confidence
) VALUES
(
    'e3100000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001', 'factor_pair_error',
    '{"selected_option":"A"}'::jsonb,
    'The factor pair may not preserve both the sum and product.',
    'For x²−5x+6, the pair must multiply to 6 and add to −5. The pair 1 and 6 multiplies to 6 but adds to 7, so it cannot be the roots.',
    '(x−2)(x−3)=0 gives roots 2 and 3: their product is 6 and their sum is 5, matching the coefficients with the required negative signs.',
    'Find two integers whose product is 12 and whose sum is −7. What roots do they give?', 0.95
),
(
    'e3100000-0000-4000-8000-000000000002',
    'd2000000-0000-4000-8000-000000000001', 'sign_error',
    '{"selected_option":"C"}'::jsonb,
    'The signs of roots may have been copied from the factors incorrectly.',
    'The factorisation (x−2)(x−3)=0 gives x=2 or x=3. Setting a factor to zero changes the sign of its constant.',
    'From (x+4)=0, solve by subtracting 4: x=−4.',
    'If (x−7)(x+2)=0, what are both roots?', 0.95
),
(
    'e3100000-0000-4000-8000-000000000003',
    'd2000000-0000-4000-8000-000000000002', 'equal_vs_distinct_roots',
    '{"selected_option":"B"}'::jsonb,
    'A positive discriminant may be confused with a zero discriminant.',
    'For 2x²+3x+1, D=b²−4ac=9−8=1. Since D is positive, the equation has two distinct real roots, not equal roots.',
    'Compare D=0 and D=9 for two quadratics: how many real roots does each have?',
    'What does the discriminant tell you when D=16?', 0.96
),
(
    'e3100000-0000-4000-8000-000000000004',
    'd2000000-0000-4000-8000-000000000002', 'discriminant_sign_error',
    '{"selected_option":"C"}'::jsonb,
    'A positive discriminant may be interpreted as no real roots.',
    'A negative discriminant means no real roots. Here D=1 is positive, so there are two distinct real roots.',
    'For x²−5x+6=0, D=25−24=1>0, so two distinct real roots exist.',
    'For D=−4, are there real roots? Explain using the sign.', 0.96
),
(
    'e3100000-0000-4000-8000-000000000005',
    'd2000000-0000-4000-8000-000000000003', 'equal_vs_distinct_roots',
    '{"selected_options":["A","B"]}'::jsonb,
    'The zero-discriminant case may be confused with the negative-discriminant case.',
    'A has D=−4 and no real roots. B has D=0 and one repeated real root. Only A and D have no real roots.',
    'For x²−4x+4=0, D=16−16=0, so its two roots are equal and real.',
    'Classify x²+2x+1=0 using its discriminant.', 0.90
),
(
    'e3100000-0000-4000-8000-000000000006',
    'd2000000-0000-4000-8000-000000000003', 'discriminant_sign_error',
    '{"selected_options":["C"]}'::jsonb,
    'A positive discriminant may be mistaken for no real roots.',
    'C is x²−9=0, whose discriminant is 36, a positive value. It has two distinct real roots, so it should not be selected.',
    'For x²−16=0, compute D and state the number of real roots.',
    'What root types correspond to a positive discriminant?', 0.90
)
ON CONFLICT (question_id, misconception_code, answer_pattern) DO NOTHING;

CREATE FUNCTION private.answer_matches_misconception_rule(p_answer jsonb, p_pattern jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN pg_catalog.jsonb_typeof(p_answer->'selected_options') = 'array'
         AND pg_catalog.jsonb_typeof(p_pattern->'selected_options') = 'array'
        THEN (
            SELECT COALESCE(pg_catalog.jsonb_agg(v.value ORDER BY v.value), '[]'::jsonb)
            FROM pg_catalog.jsonb_array_elements_text(p_answer->'selected_options') AS v(value)
        ) = (
            SELECT COALESCE(pg_catalog.jsonb_agg(v.value ORDER BY v.value), '[]'::jsonb)
            FROM pg_catalog.jsonb_array_elements_text(p_pattern->'selected_options') AS v(value)
        )
        ELSE p_answer = p_pattern
    END;
$$;
REVOKE ALL ON FUNCTION private.answer_matches_misconception_rule(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.generate_attempt_diagnoses()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_group record;
BEGIN
    IF NEW.status <> 'graded' OR OLD.status = 'graded' THEN
        RETURN NEW;
    END IF;

    FOR v_group IN
        SELECT q.topic_id, rule.misconception_code, rule.summary,
               pg_catalog.max(rule.confidence) AS confidence,
               pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                   'response_id', r.id,
                   'question_id', q.id,
                   'prompt', q.prompt,
                   'submitted_answer', r.answer,
                   'correct_answer', k.answer_config,
                   'explanation', g.explanation,
                   'corrective_example', rule.corrective_example,
                   'followup_question', rule.followup_question,
                   'rule_based', true
               ) ORDER BY aq.position) AS evidence_items
        FROM public.responses AS r
        JOIN public.assessment_questions AS aq
          ON aq.assessment_id = r.assessment_id AND aq.question_id = r.question_id
        JOIN public.questions AS q ON q.id = r.question_id
        JOIN public.question_answer_keys AS k ON k.question_id = q.id
        JOIN public.question_guidance AS g ON g.question_id = q.id
        JOIN private.misconception_rules AS rule
          ON rule.question_id = q.id AND rule.is_active
         AND private.answer_matches_misconception_rule(r.answer, rule.answer_pattern)
         AND rule.misconception_code = ANY(g.misconception_tags)
        WHERE r.attempt_id = NEW.id
          AND r.is_answered
          AND r.is_correct IS FALSE
        GROUP BY q.topic_id, rule.misconception_code, rule.summary
    LOOP
        INSERT INTO public.diagnoses (
            source_attempt_id, topic_id, misconception_code, summary, evidence, confidence
        ) VALUES (
            NEW.id, v_group.topic_id, v_group.misconception_code, v_group.summary,
            pg_catalog.jsonb_build_object('rule_based', true, 'matches', v_group.evidence_items),
            v_group.confidence
        )
        ON CONFLICT (source_attempt_id, topic_id, misconception_code) DO UPDATE
        SET summary = EXCLUDED.summary,
            evidence = EXCLUDED.evidence,
            confidence = EXCLUDED.confidence;
    END LOOP;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.generate_attempt_diagnoses() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER assessment_attempt_generate_diagnoses
AFTER UPDATE OF status ON public.assessment_attempts
FOR EACH ROW EXECUTE FUNCTION private.generate_attempt_diagnoses();

CREATE OR REPLACE FUNCTION public.get_student_diagnoses(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_status text;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    SELECT aa.status INTO v_status
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id AND aa.student_id = (SELECT auth.uid());
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attempt not found for current student' USING ERRCODE = '42501';
    END IF;
    IF v_status <> 'graded' THEN
        RAISE EXCEPTION 'Diagnoses are available after assessment completion' USING ERRCODE = '55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'attempt_id', p_attempt_id,
        'diagnoses', COALESCE((
            SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'id', d.id, 'topic_id', d.topic_id, 'misconception_code', d.misconception_code,
                'summary', d.summary, 'evidence', d.evidence, 'confidence', d.confidence,
                'created_at', d.created_at
            ) ORDER BY d.misconception_code)
            FROM public.diagnoses AS d WHERE d.source_attempt_id = p_attempt_id
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_class_misconception_summary(
    p_class_id uuid,
    p_assessment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_teacher() OR NOT private.owns_class(p_class_id) THEN
        RAISE EXCEPTION 'Only the owning teacher can view this class summary' USING ERRCODE = '42501';
    END IF;
    IF p_assessment_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.assessments AS a
        WHERE a.id = p_assessment_id AND a.class_id = p_class_id
    ) THEN
        RAISE EXCEPTION 'Assessment is not part of this class' USING ERRCODE = '42501';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'class_id', p_class_id,
        'assessment_id', p_assessment_id,
        'diagnoses', COALESCE((
            SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'topic_id', grouped.topic_id,
                'misconception_code', grouped.misconception_code,
                'summary', grouped.summary,
                'affected_students', grouped.affected_students,
                'evidence_count', grouped.evidence_count
            ) ORDER BY grouped.affected_students DESC, grouped.misconception_code)
            FROM (
                SELECT d.topic_id, d.misconception_code, d.summary,
                       pg_catalog.count(DISTINCT aa.student_id) AS affected_students,
                       pg_catalog.sum(pg_catalog.jsonb_array_length(d.evidence->'matches')) AS evidence_count
                FROM public.diagnoses AS d
                JOIN public.assessment_attempts AS aa ON aa.id = d.source_attempt_id
                JOIN public.assessments AS a ON a.id = aa.assessment_id
                WHERE a.class_id = p_class_id AND aa.status = 'graded'
                  AND (p_assessment_id IS NULL OR a.id = p_assessment_id)
                GROUP BY d.topic_id, d.misconception_code, d.summary
            ) AS grouped
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_recent_diagnoses(p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 50' USING ERRCODE = '22023';
    END IF;
    RETURN COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'attempt_id', recent.id,
            'assessment_title', recent.assessment_title,
            'submitted_at', recent.submitted_at,
            'score_percent', recent.score_percent,
            'diagnoses', recent.diagnoses
        ) ORDER BY recent.submitted_at DESC)
        FROM (
            SELECT aa.id, a.title AS assessment_title, aa.submitted_at, aa.score_percent,
                (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'id', d.id, 'topic_id', d.topic_id,
                    'misconception_code', d.misconception_code, 'summary', d.summary,
                    'evidence', d.evidence, 'confidence', d.confidence
                ) ORDER BY d.misconception_code)
                 FROM public.diagnoses AS d WHERE d.source_attempt_id = aa.id) AS diagnoses
            FROM public.assessment_attempts AS aa
            JOIN public.assessments AS a ON a.id = aa.assessment_id
            WHERE aa.student_id = (SELECT auth.uid()) AND aa.status = 'graded'
              AND EXISTS (SELECT 1 FROM public.diagnoses AS d WHERE d.source_attempt_id = aa.id)
            ORDER BY aa.submitted_at DESC, aa.id
            LIMIT p_limit
        ) AS recent
    ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_student_diagnoses(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_class_misconception_summary(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_recent_diagnoses(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_diagnoses(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_misconception_summary(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_recent_diagnoses(integer) TO authenticated;

COMMIT;
