-- Stage 2: EduDrishti diagnostic assessment engine.
-- Additive extension of Stage 1. Correct answers and instructional guidance remain
-- in separate protected tables; all grading is performed by database functions.
BEGIN;

-- Add curriculum and fixture metadata to the question bank. Seed questions have no
-- teacher owner and can only be written by a trusted migration/service role.
ALTER TABLE public.questions
    ALTER COLUMN author_teacher_id DROP NOT NULL,
    ADD COLUMN difficulty smallint NOT NULL DEFAULT 1,
    ADD COLUMN concept text NOT NULL DEFAULT 'general',
    ADD COLUMN content_source text NOT NULL DEFAULT 'teacher_authored',
    ADD CONSTRAINT questions_difficulty_check CHECK (difficulty BETWEEN 1 AND 5),
    ADD CONSTRAINT questions_concept_check
        CHECK (char_length(pg_catalog.btrim(concept)) BETWEEN 1 AND 100),
    ADD CONSTRAINT questions_content_source_check
        CHECK (content_source IN ('teacher_authored', 'development_fixture')),
    ADD CONSTRAINT questions_author_source_check CHECK (
        (content_source = 'teacher_authored' AND author_teacher_id IS NOT NULL)
        OR (content_source = 'development_fixture' AND author_teacher_id IS NULL)
    );

-- Explanations and misconception tags are not placed on the student-readable
-- questions table. Students receive them only from the completed-results RPC.
CREATE TABLE public.question_guidance (
    question_id uuid PRIMARY KEY REFERENCES public.questions (id) ON DELETE CASCADE,
    explanation text NOT NULL CHECK (char_length(explanation) BETWEEN 1 AND 5000),
    misconception_tags text[] NOT NULL DEFAULT '{}'::text[],
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT question_guidance_tags_check CHECK (
        pg_catalog.cardinality(misconception_tags) <= 16
        AND pg_catalog.array_position(misconception_tags, NULL::text) IS NULL
    )
);
CREATE TRIGGER question_guidance_set_updated_at BEFORE UPDATE ON public.question_guidance
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

-- A published development template is independent of class ownership; ordinary
-- teacher-authored assessments remain class-scoped and teacher-owned.
ALTER TABLE public.assessments
    ALTER COLUMN class_id DROP NOT NULL,
    ALTER COLUMN created_by_teacher_id DROP NOT NULL,
    ADD COLUMN is_template boolean NOT NULL DEFAULT false,
    ADD COLUMN content_source text NOT NULL DEFAULT 'teacher_authored',
    ADD CONSTRAINT assessments_content_source_check
        CHECK (content_source IN ('teacher_authored', 'development_fixture')),
    ADD CONSTRAINT assessments_template_scope_check CHECK (
        (is_template AND class_id IS NULL AND created_by_teacher_id IS NULL
            AND content_source = 'development_fixture')
        OR (NOT is_template AND class_id IS NOT NULL AND created_by_teacher_id IS NOT NULL
            AND content_source = 'teacher_authored')
    );

-- Persist whether an item was unanswered and its earned points. A NULL answered_at
-- on a completion-generated placeholder distinguishes it from a submitted answer.
ALTER TABLE public.responses
    ALTER COLUMN answered_at DROP NOT NULL,
    ADD COLUMN is_answered boolean NOT NULL DEFAULT true,
    ADD COLUMN points_earned numeric(7, 2),
    ADD CONSTRAINT responses_points_earned_check
        CHECK (points_earned IS NULL OR points_earned >= 0);

CREATE INDEX questions_topic_difficulty_idx
    ON public.questions (topic_id, difficulty, id) WHERE is_active;
CREATE INDEX assessments_template_status_idx
    ON public.assessments (status, created_at DESC) WHERE is_template;

-- Deterministic normalization for exact short-text answers. Whitespace and letter
-- case are ignored; mathematical equivalence beyond listed accepted forms is not.
CREATE FUNCTION private.normalize_short_text(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.btrim(p_value), '[[:space:]]+', '', 'g'));
$$;

CREATE FUNCTION private.jsonb_key_count(p_value jsonb)
RETURNS integer
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
    SELECT pg_catalog.count(*)::integer
    FROM pg_catalog.jsonb_object_keys(p_value) AS key_row;
$$;

CREATE FUNCTION private.answer_config_is_valid(
    p_question_type text,
    p_options jsonb,
    p_config jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_count integer;
    v_distinct_count integer;
BEGIN
    IF p_config IS NULL OR pg_catalog.jsonb_typeof(p_config) <> 'object' THEN
        RETURN false;
    END IF;

    IF p_question_type = 'single_choice' THEN
        RETURN private.jsonb_key_count(p_config) = 1
            AND p_config ? 'correct_option'
            AND pg_catalog.jsonb_typeof(p_config -> 'correct_option') = 'string'
            AND EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_options) AS option_row(value)
                WHERE pg_catalog.jsonb_typeof(option_row.value -> 'id') = 'string'
                  AND option_row.value ->> 'id' = p_config ->> 'correct_option'
            );
    ELSIF p_question_type = 'multiple_choice' THEN
        IF private.jsonb_key_count(p_config) <> 1
           OR NOT (p_config ? 'correct_options')
           OR pg_catalog.jsonb_typeof(p_config -> 'correct_options') <> 'array'
           OR pg_catalog.jsonb_array_length(p_config -> 'correct_options') = 0
           OR EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_config -> 'correct_options') AS answer_row(value)
                WHERE pg_catalog.jsonb_typeof(answer_row.value) <> 'string'
           ) THEN
            RETURN false;
        END IF;

        SELECT pg_catalog.count(*), pg_catalog.count(DISTINCT answer_row.value)
        INTO v_count, v_distinct_count
        FROM pg_catalog.jsonb_array_elements_text(p_config -> 'correct_options') AS answer_row(value);
        IF v_count <> v_distinct_count THEN
            RETURN false;
        END IF;
        RETURN NOT EXISTS (
            SELECT 1
            FROM pg_catalog.jsonb_array_elements_text(p_config -> 'correct_options') AS answer_row(value)
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_options) AS option_row(value)
                WHERE pg_catalog.jsonb_typeof(option_row.value -> 'id') = 'string'
                  AND option_row.value ->> 'id' = answer_row.value
            )
        );
    ELSIF p_question_type = 'numeric' THEN
        IF private.jsonb_key_count(p_config) NOT IN (1, 2)
           OR NOT (p_config ? 'value')
           OR pg_catalog.jsonb_typeof(p_config -> 'value') <> 'number' THEN
            RETURN false;
        END IF;
        IF p_config ? 'tolerance' THEN
            RETURN private.jsonb_key_count(p_config) = 2
                AND pg_catalog.jsonb_typeof(p_config -> 'tolerance') = 'number'
                AND (p_config ->> 'tolerance')::numeric BETWEEN 0 AND 1;
        END IF;
        RETURN true;
    ELSIF p_question_type = 'short_text' THEN
        IF private.jsonb_key_count(p_config) <> 1
           OR NOT (p_config ? 'accepted_answers')
           OR pg_catalog.jsonb_typeof(p_config -> 'accepted_answers') <> 'array'
           OR pg_catalog.jsonb_array_length(p_config -> 'accepted_answers') = 0
           OR EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_config -> 'accepted_answers') AS answer_row(value)
                WHERE pg_catalog.jsonb_typeof(answer_row.value) <> 'string'
                   OR pg_catalog.char_length(pg_catalog.btrim(answer_row.value #>> '{}')) NOT BETWEEN 1 AND 500
           ) THEN
            RETURN false;
        END IF;
        SELECT pg_catalog.count(*),
               pg_catalog.count(DISTINCT private.normalize_short_text(answer_row.value #>> '{}'))
        INTO v_count, v_distinct_count
        FROM pg_catalog.jsonb_array_elements(p_config -> 'accepted_answers') AS answer_row(value);
        RETURN v_count = v_distinct_count;
    END IF;

    RETURN false;
EXCEPTION
    WHEN invalid_parameter_value OR invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN false;
END;
$$;

CREATE FUNCTION private.answer_is_valid(
    p_question_type text,
    p_options jsonb,
    p_answer jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_count integer;
    v_distinct_count integer;
BEGIN
    IF p_answer IS NULL OR pg_catalog.jsonb_typeof(p_answer) <> 'object' THEN
        RETURN false;
    END IF;

    IF p_question_type = 'single_choice' THEN
        RETURN private.jsonb_key_count(p_answer) = 1
            AND p_answer ? 'selected_option'
            AND pg_catalog.jsonb_typeof(p_answer -> 'selected_option') = 'string'
            AND pg_catalog.char_length(p_answer ->> 'selected_option') BETWEEN 1 AND 80
            AND EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_options) AS option_row(value)
                WHERE pg_catalog.jsonb_typeof(option_row.value -> 'id') = 'string'
                  AND option_row.value ->> 'id' = p_answer ->> 'selected_option'
            );
    ELSIF p_question_type = 'multiple_choice' THEN
        IF private.jsonb_key_count(p_answer) <> 1
           OR NOT (p_answer ? 'selected_options')
           OR pg_catalog.jsonb_typeof(p_answer -> 'selected_options') <> 'array'
           OR pg_catalog.jsonb_array_length(p_answer -> 'selected_options') NOT BETWEEN 1 AND 16
           OR EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_answer -> 'selected_options') AS answer_row(value)
                WHERE pg_catalog.jsonb_typeof(answer_row.value) <> 'string'
           ) THEN
            RETURN false;
        END IF;
        SELECT pg_catalog.count(*), pg_catalog.count(DISTINCT answer_row.value)
        INTO v_count, v_distinct_count
        FROM pg_catalog.jsonb_array_elements_text(p_answer -> 'selected_options') AS answer_row(value);
        IF v_count <> v_distinct_count THEN
            RETURN false;
        END IF;
        RETURN NOT EXISTS (
            SELECT 1
            FROM pg_catalog.jsonb_array_elements_text(p_answer -> 'selected_options') AS answer_row(value)
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_catalog.jsonb_array_elements(p_options) AS option_row(value)
                WHERE pg_catalog.jsonb_typeof(option_row.value -> 'id') = 'string'
                  AND option_row.value ->> 'id' = answer_row.value
            )
        );
    ELSIF p_question_type = 'numeric' THEN
        RETURN private.jsonb_key_count(p_answer) = 1
            AND p_answer ? 'value'
            AND pg_catalog.jsonb_typeof(p_answer -> 'value') = 'number';
    ELSIF p_question_type = 'short_text' THEN
        RETURN private.jsonb_key_count(p_answer) = 1
            AND p_answer ? 'value'
            AND pg_catalog.jsonb_typeof(p_answer -> 'value') = 'string'
            AND pg_catalog.char_length(pg_catalog.btrim(p_answer ->> 'value')) BETWEEN 1 AND 1000;
    END IF;

    RETURN false;
EXCEPTION
    WHEN invalid_parameter_value OR invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN false;
END;
$$;

CREATE FUNCTION private.answer_is_correct(
    p_question_type text,
    p_options jsonb,
    p_answer jsonb,
    p_config jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_submitted text[];
    v_correct text[];
BEGIN
    IF NOT private.answer_is_valid(p_question_type, p_options, p_answer)
       OR NOT private.answer_config_is_valid(p_question_type, p_options, p_config) THEN
        RETURN false;
    END IF;

    IF p_question_type = 'single_choice' THEN
        RETURN p_answer ->> 'selected_option' = p_config ->> 'correct_option';
    ELSIF p_question_type = 'multiple_choice' THEN
        SELECT pg_catalog.array_agg(answer_row.value ORDER BY answer_row.value)
        INTO v_submitted
        FROM pg_catalog.jsonb_array_elements_text(p_answer -> 'selected_options') AS answer_row(value);
        SELECT pg_catalog.array_agg(answer_row.value ORDER BY answer_row.value)
        INTO v_correct
        FROM pg_catalog.jsonb_array_elements_text(p_config -> 'correct_options') AS answer_row(value);
        RETURN v_submitted = v_correct;
    ELSIF p_question_type = 'numeric' THEN
        RETURN pg_catalog.abs((p_answer ->> 'value')::numeric - (p_config ->> 'value')::numeric)
            <= COALESCE((p_config ->> 'tolerance')::numeric, 0);
    ELSIF p_question_type = 'short_text' THEN
        RETURN EXISTS (
            SELECT 1
            FROM pg_catalog.jsonb_array_elements_text(p_config -> 'accepted_answers') AS answer_row(value)
            WHERE private.normalize_short_text(answer_row.value)
                = private.normalize_short_text(p_answer ->> 'value')
        );
    END IF;

    RETURN false;
EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN false;
END;
$$;

CREATE FUNCTION private.question_has_valid_answer_config(p_question_id uuid, p_config jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.questions AS q
        WHERE q.id = p_question_id
          AND private.answer_config_is_valid(q.question_type, q.options, p_config)
    );
$$;

CREATE FUNCTION private.is_current_user_student()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles AS p
        WHERE p.user_id = (SELECT auth.uid()) AND p.app_role = 'student'
    );
$$;

CREATE FUNCTION private.assessment_is_publishable(p_assessment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.assessment_questions AS aq
        WHERE aq.assessment_id = p_assessment_id
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public.assessment_questions AS aq
        JOIN public.questions AS q ON q.id = aq.question_id
        LEFT JOIN public.question_answer_keys AS k ON k.question_id = q.id
        LEFT JOIN public.question_guidance AS g ON g.question_id = q.id
        WHERE aq.assessment_id = p_assessment_id
          AND (NOT q.is_active
               OR k.question_id IS NULL
               OR g.question_id IS NULL
               OR NOT private.answer_config_is_valid(q.question_type, q.options, k.answer_config))
    );
$$;

CREATE OR REPLACE FUNCTION private.can_view_assessment(p_assessment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assessments AS a
        WHERE a.id = p_assessment_id
          AND (
              private.owns_class(a.class_id)
              OR (
                  a.is_template
                  AND a.status = 'published'
                  AND (private.is_current_user_student() OR private.is_current_user_teacher())
              )
              OR (
                  a.class_id IS NOT NULL
                  AND a.status = 'published'
                  AND private.is_active_student_in_class(a.class_id, (SELECT auth.uid()))
              )
          )
    );
$$;

CREATE FUNCTION private.can_attach_question(p_question_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.is_current_user_teacher() AND EXISTS (
        SELECT 1
        FROM public.questions AS q
        WHERE q.id = p_question_id
          AND q.is_active
          AND (
              q.author_teacher_id = (SELECT auth.uid())
              OR q.content_source = 'development_fixture'
          )
    );
$$;

CREATE OR REPLACE FUNCTION private.can_view_question(p_question_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.is_question_author(p_question_id)
        OR EXISTS (
            SELECT 1
            FROM public.questions AS q
            WHERE q.id = p_question_id
              AND q.is_active
              AND q.content_source = 'development_fixture'
              AND private.is_current_user_teacher()
        )
        OR EXISTS (
            SELECT 1
            FROM public.assessment_questions AS aq
            JOIN public.assessments AS a ON a.id = aq.assessment_id
            WHERE aq.question_id = p_question_id
              AND private.can_view_assessment(a.id)
        );
$$;

CREATE OR REPLACE FUNCTION private.can_view_attempt(p_attempt_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        WHERE aa.id = p_attempt_id
          AND (
              aa.student_id = (SELECT auth.uid())
              OR (a.class_id IS NOT NULL AND private.owns_class(a.class_id))
          )
    );
$$;

CREATE FUNCTION private.can_view_question_guidance(p_question_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.is_question_author(p_question_id)
        OR (
            private.is_current_user_teacher()
            AND EXISTS (
                SELECT 1 FROM public.questions AS q
                WHERE q.id = p_question_id AND q.content_source = 'development_fixture'
        )
    );
$$;

ALTER TABLE public.question_guidance ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.question_guidance FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.question_guidance TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.question_guidance TO authenticated;
CREATE POLICY question_guidance_select_teacher
    ON public.question_guidance FOR SELECT TO authenticated
    USING (private.can_view_question_guidance(question_id));
CREATE POLICY question_guidance_insert_author
    ON public.question_guidance FOR INSERT TO authenticated
    WITH CHECK (private.can_manage_question(question_id));
CREATE POLICY question_guidance_update_author
    ON public.question_guidance FOR UPDATE TO authenticated
    USING (private.can_manage_question(question_id))
    WITH CHECK (private.can_manage_question(question_id));

ALTER POLICY question_answer_keys_insert_author ON public.question_answer_keys
    WITH CHECK (
        private.can_manage_question(question_id)
        AND private.question_has_valid_answer_config(question_id, answer_config)
    );
ALTER POLICY question_answer_keys_update_author ON public.question_answer_keys
    USING (private.can_manage_question(question_id))
    WITH CHECK (
        private.can_manage_question(question_id)
        AND private.question_has_valid_answer_config(question_id, answer_config)
    );
ALTER POLICY assessment_questions_insert_teacher_draft ON public.assessment_questions
    WITH CHECK (
        private.can_manage_assessment(assessment_id)
        AND private.can_attach_question(question_id)
    );
ALTER POLICY assessment_questions_update_teacher_draft ON public.assessment_questions
    USING (
        private.can_manage_assessment(assessment_id)
        AND private.can_attach_question(question_id)
    )
    WITH CHECK (
        private.can_manage_assessment(assessment_id)
        AND private.can_attach_question(question_id)
    );
ALTER POLICY assessments_update_unstarted_draft ON public.assessments
    USING (private.can_manage_assessment(id))
    WITH CHECK (
        created_by_teacher_id = (SELECT auth.uid())
        AND private.owns_class(class_id)
        AND status IN ('draft', 'published')
        AND (status <> 'published' OR private.assessment_is_publishable(id))
    );

-- Reviewed development question set: factorisation, real roots, discriminant, and
-- a contextual problem. These are educational fixtures, not learner-performance data.
INSERT INTO public.questions (
    id, author_teacher_id, topic_id, question_type, prompt, options, is_active,
    difficulty, concept, content_source
)
VALUES
(
    'd2000000-0000-4000-8000-000000000001', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'single_choice', 'Solve x^2 - 5x + 6 = 0. Choose the pair of roots.',
   pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id','A','text','1 and 6'),
        pg_catalog.jsonb_build_object('id','B','text','2 and 3'),
        pg_catalog.jsonb_build_object('id','C','text','-2 and -3'),
        pg_catalog.jsonb_build_object('id','D','text','3 and -6')
    ),
    true, 1, 'factorisation_roots', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000002', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'single_choice', 'What is the nature of the roots of 2x^2 + 3x + 1 = 0?',
   pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id','A','text','Two distinct real roots'),
        pg_catalog.jsonb_build_object('id','B','text','Two equal real roots'),
        pg_catalog.jsonb_build_object('id','C','text','No real roots'),
        pg_catalog.jsonb_build_object('id','D','text','Not a quadratic equation')
    ),
    true, 1, 'discriminant_nature', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000003', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'multiple_choice', 'Select every equation that has no real roots.',
   pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id','A','text','x^2 + 1 = 0'),
        pg_catalog.jsonb_build_object('id','B','text','x^2 - 4x + 4 = 0'),
        pg_catalog.jsonb_build_object('id','C','text','x^2 - 9 = 0'),
        pg_catalog.jsonb_build_object('id','D','text','3x^2 + 2x + 1 = 0')
    ),
    true, 3, 'discriminant_sign', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000004', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'numeric', 'Find the discriminant of 2x^2 + 3x + 1 = 0.', '[]'::jsonb,
    true, 1, 'discriminant_calculation', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000005', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'numeric', 'Find the larger root of 2x^2 - 5x + 3 = 0.', '[]'::jsonb,
    true, 2, 'factorisation_roots', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000006', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'short_text', 'Write the monic quadratic equation in standard form whose roots are 2 and 3.', '[]'::jsonb,
    true, 2, 'roots_to_equation', 'development_fixture'
),
(
    'd2000000-0000-4000-8000-000000000007', NULL,
    (SELECT t.id FROM public.topics AS t WHERE t.subject = 'Mathematics' AND t.grade_level = 10 AND t.code = 'quadratic-equations' LIMIT 1),
    'numeric', 'A rectangle has area 50 m^2 and its length is 5 m greater than its width. Find its positive width in metres.', '[]'::jsonb,
    true, 2, 'situational_modelling', 'development_fixture'
);

INSERT INTO public.question_answer_keys (question_id, answer_config, rationale) VALUES
('d2000000-0000-4000-8000-000000000001',pg_catalog.jsonb_build_object('correct_option','B'), 'x^2 - 5x + 6 = (x - 2)(x - 3), so the roots are 2 and 3.'),
('d2000000-0000-4000-8000-000000000002',pg_catalog.jsonb_build_object('correct_option','A'), 'The discriminant is 3^2 - 4(2)(1) = 1 > 0, so there are two distinct real roots.'),
('d2000000-0000-4000-8000-000000000003',pg_catalog.jsonb_build_object('correct_options',pg_catalog.jsonb_build_array('A','D')), 'The discriminants are -4 and -8 for A and D; both are negative, so neither equation has real roots.'),
('d2000000-0000-4000-8000-000000000004',pg_catalog.jsonb_build_object('value',1,'tolerance',0), 'For a=2, b=3, c=1, D=b^2-4ac=9-8=1.'),
('d2000000-0000-4000-8000-000000000005',pg_catalog.jsonb_build_object('value',1.5,'tolerance',0.001), '2x^2 - 5x + 3 = (2x - 3)(x - 1), so the larger root is 1.5.'),
('d2000000-0000-4000-8000-000000000006',pg_catalog.jsonb_build_object('accepted_answers',pg_catalog.jsonb_build_array('x^2 - 5x + 6 = 0')), 'A monic equation with roots 2 and 3 is (x - 2)(x - 3) = 0.'),
('d2000000-0000-4000-8000-000000000007',pg_catalog.jsonb_build_object('value',5,'tolerance',0), 'If width is x, then x(x+5)=50, so x^2+5x-50=(x+10)(x-5)=0. The positive width is 5 m.');

INSERT INTO public.question_guidance (question_id, explanation, misconception_tags) VALUES
('d2000000-0000-4000-8000-000000000001', 'Factor the trinomial: x^2 - 5x + 6 = (x - 2)(x - 3). Set each factor to zero.', ARRAY['factor_pair_error','sign_error']),
('d2000000-0000-4000-8000-000000000002', 'Compute D=b^2-4ac=9-8=1. Since D is positive, the equation has two distinct real roots.', ARRAY['coefficient_substitution_error','discriminant_sign_error']),
('d2000000-0000-4000-8000-000000000003', 'A has D=-4 and D is negative. D has 2^2-4(3)(1)=-8 and is also negative. B has equal roots; C has distinct real roots.', ARRAY['discriminant_sign_error','equal_vs_distinct_roots']),
('d2000000-0000-4000-8000-000000000004', 'Identify a=2, b=3, c=1 before substituting: D=3^2-4(2)(1)=1.', ARRAY['coefficient_substitution_error','arithmetic_error']),
('d2000000-0000-4000-8000-000000000005', 'Factor to (2x-3)(x-1)=0. The roots are 1.5 and 1; select the larger value.', ARRAY['factorisation_error','root_selection_error']),
('d2000000-0000-4000-8000-000000000006', 'For roots 2 and 3, form (x-2)(x-3)=0 and expand to x^2-5x+6=0.', ARRAY['root_sum_sign_error','standard_form_error']),
('d2000000-0000-4000-8000-000000000007', 'Let the width be x and length x+5. The area equation gives x^2+5x-50=0. Its roots are 5 and -10; reject the negative length value in this context.', ARRAY['model_equation_error','negative_contextual_root']);

INSERT INTO public.assessments (
    id, class_id, created_by_teacher_id, title, description, assessment_type,
    status, is_template, content_source
)
VALUES (
    'd3000000-0000-4000-8000-000000000001', NULL, NULL,
    'Quadratic Equations Diagnostic (Development Sample)',
    'Seven development-fixture items aligned to Class 10 factorisation, real roots, discriminant, and a contextual quadratic problem.',
    'diagnostic', 'published', true, 'development_fixture'
);

INSERT INTO public.assessment_questions (assessment_id, question_id, position, points) VALUES
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001',1,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002',2,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000003',3,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000004',4,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000005',5,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000006',6,1),
('d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000007',7,1);

CREATE OR REPLACE FUNCTION public.list_available_assessments()
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

    RETURN COALESCE((
        SELECT pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
                'assessment_id', a.id,
                'title', a.title,
                'description', a.description,
                'assessment_type', a.assessment_type,
                'class_id', a.class_id,
                'is_template', a.is_template,
                'question_count', (SELECT pg_catalog.count(*) FROM public.assessment_questions AS aq WHERE aq.assessment_id = a.id),
                'total_points', (SELECT COALESCE(pg_catalog.sum(aq.points), 0) FROM public.assessment_questions AS aq WHERE aq.assessment_id = a.id),
                'opens_at', a.opens_at,
                'closes_at', a.closes_at
            ) ORDER BY a.created_at DESC, a.id
        )
        FROM public.assessments AS a
        WHERE a.status = 'published'
          AND (a.opens_at IS NULL OR a.opens_at <= pg_catalog.now())
          AND (a.closes_at IS NULL OR a.closes_at > pg_catalog.now())
          AND (
              a.is_template
              OR (a.class_id IS NOT NULL AND private.is_active_student_in_class(a.class_id, (SELECT auth.uid())))
          )
          AND EXISTS (SELECT 1 FROM public.assessment_questions AS aq WHERE aq.assessment_id = a.id)
    ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_assessment(p_assessment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_assessment public.assessments%ROWTYPE;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;

    SELECT a.* INTO v_assessment
    FROM public.assessments AS a
    WHERE a.id = p_assessment_id
      AND a.status = 'published'
      AND (a.opens_at IS NULL OR a.opens_at <= pg_catalog.now())
      AND (a.closes_at IS NULL OR a.closes_at > pg_catalog.now())
      AND private.can_view_assessment(a.id)
      AND EXISTS (SELECT 1 FROM public.assessment_questions AS aq WHERE aq.assessment_id = a.id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment is unavailable to this student' USING ERRCODE = '42501';
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'assessment', pg_catalog.jsonb_build_object(
            'id', v_assessment.id,
            'title', v_assessment.title,
            'description', v_assessment.description,
            'assessment_type', v_assessment.assessment_type,
            'class_id', v_assessment.class_id,
            'is_template', v_assessment.is_template,
            'opens_at', v_assessment.opens_at,
            'closes_at', v_assessment.closes_at
        ),
        'questions', COALESCE((
            SELECT pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'question_id', q.id,
                    'position', aq.position,
                    'points', aq.points,
                    'question_type', q.question_type,
                    'prompt', q.prompt,
                    'options', q.options,
                    'difficulty', q.difficulty,
                    'concept', q.concept,
                    'topic', pg_catalog.jsonb_build_object('id', t.id, 'code', t.code, 'title', t.title)
                ) ORDER BY aq.position
            )
            FROM public.assessment_questions AS aq
            JOIN public.questions AS q ON q.id = aq.question_id AND q.is_active
            JOIN public.topics AS t ON t.id = q.topic_id
            WHERE aq.assessment_id = v_assessment.id
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.start_assessment(p_assessment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := (SELECT auth.uid());
    v_class_id uuid;
    v_is_template boolean;
    v_attempt_id uuid;
    v_attempt_number integer;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required to start an assessment' USING ERRCODE = '42501';
    END IF;

    SELECT a.class_id, a.is_template INTO v_class_id, v_is_template
    FROM public.assessments AS a
    WHERE a.id = p_assessment_id
      AND a.status = 'published'
      AND (a.opens_at IS NULL OR a.opens_at <= pg_catalog.now())
      AND (a.closes_at IS NULL OR a.closes_at > pg_catalog.now());
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment is unavailable' USING ERRCODE = '22023';
    END IF;
    IF NOT v_is_template
       AND (v_class_id IS NULL OR NOT private.is_active_student_in_class(v_class_id, v_user_id)) THEN
        RAISE EXCEPTION 'An active class enrollment is required' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.assessment_questions AS aq
        WHERE aq.assessment_id = p_assessment_id
    ) THEN
        RAISE EXCEPTION 'Assessment has no questions' USING ERRCODE = '55000';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_assessment_id::text || ':' || v_user_id::text, 0)
    );

    SELECT aa.id INTO v_attempt_id
    FROM public.assessment_attempts AS aa
    WHERE aa.assessment_id = p_assessment_id
      AND aa.student_id = v_user_id
      AND aa.status = 'in_progress';
    IF v_attempt_id IS NOT NULL THEN
        RETURN v_attempt_id;
    END IF;

    SELECT COALESCE(pg_catalog.max(aa.attempt_number), 0) + 1 INTO v_attempt_number
    FROM public.assessment_attempts AS aa
    WHERE aa.assessment_id = p_assessment_id AND aa.student_id = v_user_id;

    INSERT INTO public.assessment_attempts (assessment_id, student_id, attempt_number)
    VALUES (p_assessment_id, v_user_id, v_attempt_number)
    RETURNING id INTO v_attempt_id;
    RETURN v_attempt_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_response(
    p_attempt_id uuid,
    p_question_id uuid,
    p_answer jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_assessment_id uuid;
    v_status text;
    v_question_type text;
    v_options jsonb;
    v_response_id uuid;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF p_answer IS NULL OR pg_catalog.pg_column_size(p_answer) > 16384 THEN
        RAISE EXCEPTION 'Answer must be a JSON value no larger than 16 KiB' USING ERRCODE = '22023';
    END IF;

    SELECT aa.assessment_id, aa.status INTO v_assessment_id, v_status
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id AND aa.student_id = (SELECT auth.uid())
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attempt not found for current student' USING ERRCODE = '42501';
    END IF;
    IF v_status <> 'in_progress' THEN
        RAISE EXCEPTION 'Answers can only be changed during an active attempt' USING ERRCODE = '55000';
    END IF;

    SELECT q.question_type, q.options INTO v_question_type, v_options
    FROM public.assessment_questions AS aq
    JOIN public.questions AS q ON q.id = aq.question_id AND q.is_active
    WHERE aq.assessment_id = v_assessment_id AND aq.question_id = p_question_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Question is not part of this assessment' USING ERRCODE = '22023';
    END IF;
    IF NOT private.answer_is_valid(v_question_type, v_options, p_answer) THEN
        RAISE EXCEPTION 'Answer format does not match the question type' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer, is_answered, answered_at)
    VALUES (p_attempt_id, v_assessment_id, p_question_id, p_answer, true, pg_catalog.now())
    ON CONFLICT (attempt_id, question_id) DO UPDATE
        SET answer = EXCLUDED.answer,
            is_answered = true,
            answered_at = EXCLUDED.answered_at
        WHERE public.responses.graded_at IS NULL
          AND public.responses.score_percent IS NULL
    RETURNING id INTO v_response_id;

    IF v_response_id IS NULL THEN
        RAISE EXCEPTION 'A graded response cannot be changed' USING ERRCODE = '55000';
    END IF;
    RETURN v_response_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_results(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_attempt public.assessment_attempts%ROWTYPE;
    v_title text;
    v_total_points numeric;
    v_earned_points numeric;
    v_correct_count bigint;
    v_incorrect_count bigint;
    v_unanswered_count bigint;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;

    SELECT aa.* INTO v_attempt
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id AND aa.student_id = (SELECT auth.uid());
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result not found for current student' USING ERRCODE = '42501';
    END IF;
    IF v_attempt.status <> 'graded' THEN
        RAISE EXCEPTION 'Results are available after assessment completion' USING ERRCODE = '55000';
    END IF;

    SELECT a.title INTO v_title FROM public.assessments AS a WHERE a.id = v_attempt.assessment_id;
    SELECT COALESCE(pg_catalog.sum(aq.points), 0) INTO v_total_points
    FROM public.assessment_questions AS aq WHERE aq.assessment_id = v_attempt.assessment_id;
    SELECT COALESCE(pg_catalog.sum(r.points_earned), 0),
           pg_catalog.count(*) FILTER (WHERE r.is_correct),
           pg_catalog.count(*) FILTER (WHERE r.is_answered AND NOT r.is_correct),
           pg_catalog.count(*) FILTER (WHERE NOT r.is_answered)
    INTO v_earned_points, v_correct_count, v_incorrect_count, v_unanswered_count
    FROM public.responses AS r
    WHERE r.attempt_id = p_attempt_id;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'attempt', pg_catalog.jsonb_build_object(
            'id', v_attempt.id,
            'assessment_id', v_attempt.assessment_id,
            'assessment_title', v_title,
            'attempt_number', v_attempt.attempt_number,
            'status', v_attempt.status,
            'started_at', v_attempt.started_at,
            'submitted_at', v_attempt.submitted_at,
            'score_percent', v_attempt.score_percent
        ),
        'summary', pg_catalog.jsonb_build_object(
            'earned_points', COALESCE(v_earned_points, 0),
            'total_points', v_total_points,
            'correct_count', COALESCE(v_correct_count, 0),
            'incorrect_count', COALESCE(v_incorrect_count, 0),
            'unanswered_count', COALESCE(v_unanswered_count, 0)
        ),
        'items', COALESCE((
            SELECT pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'question_id', q.id,
                    'position', aq.position,
                    'question_type', q.question_type,
                    'prompt', q.prompt,
                    'answer', r.answer,
                    'is_answered', r.is_answered,
                    'is_correct', r.is_correct,
                    'score_percent', r.score_percent,
                    'points_earned', r.points_earned,
                    'points_possible', aq.points,
                    'correct_answer', k.answer_config,
                    'explanation', g.explanation,
                    'misconception_tags', pg_catalog.to_jsonb(g.misconception_tags)
                ) ORDER BY aq.position
            )
            FROM public.assessment_questions AS aq
            JOIN public.questions AS q ON q.id = aq.question_id
            JOIN public.question_answer_keys AS k ON k.question_id = q.id
            JOIN public.question_guidance AS g ON g.question_id = q.id
            JOIN public.responses AS r
              ON r.attempt_id = p_attempt_id
             AND r.assessment_id = aq.assessment_id
             AND r.question_id = aq.question_id
            WHERE aq.assessment_id = v_attempt.assessment_id
        ), '[]'::jsonb)
    );
END;
$$;

CREATE FUNCTION public.complete_assessment(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_assessment_id uuid;
    v_status text;
    v_now timestamptz := pg_catalog.now();
    v_total numeric;
    v_earned numeric;
    v_score numeric(5, 2);
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;

    SELECT aa.assessment_id, aa.status INTO v_assessment_id, v_status
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id AND aa.student_id = (SELECT auth.uid())
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attempt not found for current student' USING ERRCODE = '42501';
    END IF;
    IF v_status = 'graded' THEN
        RETURN public.get_student_results(p_attempt_id);
    END IF;
    IF v_status NOT IN ('in_progress', 'submitted') THEN
        RAISE EXCEPTION 'Only an active or submitted attempt can be completed' USING ERRCODE = '55000';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.assessment_questions AS aq WHERE aq.assessment_id = v_assessment_id
    ) THEN
        RAISE EXCEPTION 'Assessment has no questions' USING ERRCODE = '55000';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM public.assessment_questions AS aq
        JOIN public.questions AS q ON q.id = aq.question_id
        LEFT JOIN public.question_answer_keys AS k ON k.question_id = q.id
        WHERE aq.assessment_id = v_assessment_id
          AND (k.question_id IS NULL
               OR NOT private.answer_config_is_valid(q.question_type, q.options, k.answer_config))
    ) THEN
        RAISE EXCEPTION 'Assessment contains a question without a valid answer key' USING ERRCODE = '55000';
    END IF;

    -- Missing responses become explicit unanswered rows and earn zero points.
    INSERT INTO public.responses (
        attempt_id, assessment_id, question_id, answer, is_answered, answered_at
    )
    SELECT p_attempt_id, v_assessment_id, aq.question_id, '{}'::jsonb, false, NULL
    FROM public.assessment_questions AS aq
    WHERE aq.assessment_id = v_assessment_id
      AND NOT EXISTS (
          SELECT 1 FROM public.responses AS r
          WHERE r.attempt_id = p_attempt_id AND r.question_id = aq.question_id
      );

    UPDATE public.responses AS r
    SET is_correct = CASE
            WHEN r.is_answered THEN private.answer_is_correct(q.question_type, q.options, r.answer, k.answer_config)
            ELSE false
        END,
        score_percent = CASE
            WHEN r.is_answered AND private.answer_is_correct(q.question_type, q.options, r.answer, k.answer_config)
            THEN 100 ELSE 0
        END,
        points_earned = CASE
            WHEN r.is_answered AND private.answer_is_correct(q.question_type, q.options, r.answer, k.answer_config)
            THEN aq.points ELSE 0
        END,
        feedback = pg_catalog.jsonb_build_object(
            'is_answered', r.is_answered,
            'explanation', g.explanation,
            'misconception_tags', pg_catalog.to_jsonb(g.misconception_tags)
        ),
        graded_at = v_now
    FROM public.assessment_questions AS aq
    JOIN public.questions AS q ON q.id = aq.question_id
    JOIN public.question_answer_keys AS k ON k.question_id = q.id
    JOIN public.question_guidance AS g ON g.question_id = q.id
    WHERE r.attempt_id = p_attempt_id
      AND aq.assessment_id = v_assessment_id
      AND aq.question_id = r.question_id;

    SELECT COALESCE(pg_catalog.sum(aq.points), 0),
           COALESCE(pg_catalog.sum(r.points_earned), 0)
    INTO v_total, v_earned
    FROM public.assessment_questions AS aq
    JOIN public.responses AS r
      ON r.attempt_id = p_attempt_id
     AND r.assessment_id = aq.assessment_id
     AND r.question_id = aq.question_id
    WHERE aq.assessment_id = v_assessment_id;
    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Assessment has no positive point total' USING ERRCODE = '55000';
    END IF;
    v_score := pg_catalog.round((v_earned / v_total) * 100, 2);

    UPDATE public.assessment_attempts
    SET status = 'graded',
        submitted_at = COALESCE(submitted_at, v_now),
        score_percent = v_score,
        updated_at = v_now
    WHERE id = p_attempt_id;

    RETURN public.get_student_results(p_attempt_id);
END;
$$;

-- Preserve the Stage 1 RPC name as an idempotent alias; it now uses server grading.
CREATE OR REPLACE FUNCTION public.submit_assessment(p_attempt_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.complete_assessment(p_attempt_id);
END;
$$;

REVOKE ALL ON FUNCTION private.jsonb_key_count(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.normalize_short_text(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.answer_config_is_valid(text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.answer_is_valid(text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.answer_is_correct(text, jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.question_has_valid_answer_config(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.is_current_user_student() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.assessment_is_publishable(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_attach_question(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_view_question_guidance(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.question_has_valid_answer_config(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION private.assessment_is_publishable(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_attach_question(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_question_guidance(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_available_assessments() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_assessment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_assessment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_response(uuid, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_assessment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_assessment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_results(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_available_assessments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_response(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_results(uuid) TO authenticated;

COMMIT;
