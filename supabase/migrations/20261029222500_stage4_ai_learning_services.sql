BEGIN;

CREATE TABLE private.ai_request_buckets (
    student_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
    service_name text NOT NULL CHECK (service_name IN ('explanation', 'practice', 'practice_answer')),
    window_start timestamptz NOT NULL,
    request_count integer NOT NULL CHECK (request_count > 0),
    PRIMARY KEY (student_id, service_name, window_start)
);
REVOKE ALL ON TABLE private.ai_request_buckets FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE private.ai_learning_activities (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
    attempt_id uuid NOT NULL REFERENCES public.assessment_attempts (id) ON DELETE CASCADE,
    question_id uuid NOT NULL REFERENCES public.questions (id) ON DELETE RESTRICT,
    activity_type text NOT NULL CHECK (activity_type IN ('explanation', 'practice')),
    source text NOT NULL DEFAULT 'ai_generated' CHECK (source = 'ai_generated'),
    provider text NOT NULL DEFAULT 'google_gemini' CHECK (provider = 'google_gemini'),
    model text NOT NULL CHECK (char_length(model) BETWEEN 1 AND 100),
    prompt_version text NOT NULL CHECK (char_length(prompt_version) BETWEEN 1 AND 64),
    content jsonb NOT NULL CHECK (
        pg_catalog.jsonb_typeof(content) = 'object'
        AND pg_catalog.octet_length(content::text) <= 100000
    ),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT ai_learning_activity_attempt_question_unique UNIQUE (id, student_id)
);
REVOKE ALL ON TABLE private.ai_learning_activities FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE private.ai_practice_responses (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
    activity_id uuid NOT NULL REFERENCES private.ai_learning_activities (id) ON DELETE CASCADE,
    item_id uuid NOT NULL,
    submitted_answer jsonb NOT NULL CHECK (
        pg_catalog.jsonb_typeof(submitted_answer) = 'object'
        AND pg_catalog.octet_length(submitted_answer::text) <= 2048
    ),
    is_correct boolean NOT NULL,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);
REVOKE ALL ON TABLE private.ai_practice_responses FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.consume_ai_request(p_student_id uuid, p_service_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_limit integer;
    v_window timestamptz := pg_catalog.date_trunc('minute', pg_catalog.now());
    v_count integer;
BEGIN
    IF p_student_id IS NULL THEN
        RAISE EXCEPTION 'Student id is required' USING ERRCODE = '22023';
    END IF;
    v_limit := CASE p_service_name
        WHEN 'explanation' THEN 6
        WHEN 'practice' THEN 3
        WHEN 'practice_answer' THEN 15
        ELSE NULL
    END;
    IF v_limit IS NULL THEN
        RAISE EXCEPTION 'Unknown AI service' USING ERRCODE = '22023';
    END IF;

    DELETE FROM private.ai_request_buckets AS bucket
    WHERE bucket.student_id = p_student_id
      AND bucket.service_name = p_service_name
      AND bucket.window_start < v_window - INTERVAL '2 minutes';

    INSERT INTO private.ai_request_buckets AS bucket (student_id, service_name, window_start, request_count)
    VALUES (p_student_id, p_service_name, v_window, 1)
    ON CONFLICT (student_id, service_name, window_start)
    DO UPDATE SET request_count = bucket.request_count + 1
    RETURNING request_count INTO v_count;

    RETURN v_count <= v_limit;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_ai_request(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_ai_request(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_ai_learning_context(
    p_student_id uuid,
    p_attempt_id uuid,
    p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_context jsonb;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.assessment_attempts AS attempt
        JOIN public.responses AS response ON response.attempt_id = attempt.id
        WHERE attempt.id = p_attempt_id
          AND attempt.student_id = p_student_id
          AND attempt.status = 'graded'
          AND response.question_id = p_question_id
          AND response.is_answered
    ) THEN
        RAISE EXCEPTION 'Question is not an answered item in this student's graded attempt' USING ERRCODE = '42501';
    END IF;

    SELECT pg_catalog.jsonb_build_object(
        'topic', pg_catalog.jsonb_build_object(
            'title', topic.title,
            'subject', topic.subject,
            'grade_level', topic.grade_level,
            'code', topic.code
        ),
        'concept', question.concept,
        'difficulty', question.difficulty
    )
    INTO v_context
    FROM public.questions AS question
    JOIN public.topics AS topic ON topic.id = question.topic_id
    WHERE question.id = p_question_id AND question.is_active;

    IF v_context IS NULL THEN
        RAISE EXCEPTION 'Question context is unavailable' USING ERRCODE = '55000';
    END IF;
    RETURN v_context;
END;
$$;
REVOKE ALL ON FUNCTION public.get_ai_learning_context(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_learning_context(uuid, uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.store_ai_learning_activity(
    p_student_id uuid,
    p_attempt_id uuid,
    p_question_id uuid,
    p_activity_type text,
    p_content jsonb,
    p_model text,
    p_prompt_version text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_activity_id uuid;
BEGIN
    IF p_activity_type IS NULL OR p_activity_type NOT IN ('explanation', 'practice')
       OR p_content IS NULL
       OR pg_catalog.jsonb_typeof(p_content) <> 'object'
       OR pg_catalog.octet_length(p_content::text) > 100000
       OR p_model IS NULL OR char_length(p_model) NOT BETWEEN 1 AND 100
       OR p_prompt_version IS NULL OR char_length(p_prompt_version) NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'AI activity payload is invalid' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.assessment_attempts AS attempt
        JOIN public.responses AS response ON response.attempt_id = attempt.id
        WHERE attempt.id = p_attempt_id
          AND attempt.student_id = p_student_id
          AND attempt.status = 'graded'
          AND response.question_id = p_question_id
          AND response.is_answered
    ) THEN
        RAISE EXCEPTION 'Activity must belong to an answered item in the student's graded attempt' USING ERRCODE = '42501';
    END IF;
    IF p_activity_type = 'practice' AND CASE
        WHEN pg_catalog.jsonb_typeof(p_content->'items') = 'array'
            THEN pg_catalog.jsonb_array_length(p_content->'items') NOT BETWEEN 1 AND 3
        ELSE true
    END THEN
        RAISE EXCEPTION 'Practice content must contain one to three items' USING ERRCODE = '22023';
    END IF;

    INSERT INTO private.ai_learning_activities (
        student_id, attempt_id, question_id, activity_type, model, prompt_version, content
    ) VALUES (
        p_student_id, p_attempt_id, p_question_id, p_activity_type, p_model, p_prompt_version, p_content
    ) RETURNING id INTO v_activity_id;
    RETURN v_activity_id;
END;
$$;
REVOKE ALL ON FUNCTION public.store_ai_learning_activity(uuid, uuid, uuid, text, jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_ai_learning_activity(uuid, uuid, uuid, text, jsonb, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_ai_learning_activity(p_student_id uuid, p_activity_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_activity private.ai_learning_activities%ROWTYPE;
BEGIN
    SELECT activity.* INTO v_activity
    FROM private.ai_learning_activities AS activity
    WHERE activity.id = p_activity_id AND activity.student_id = p_student_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    RETURN pg_catalog.jsonb_build_object(
        'id', v_activity.id,
        'activity_type', v_activity.activity_type,
        'source', v_activity.source,
        'provider', v_activity.provider,
        'model', v_activity.model,
        'prompt_version', v_activity.prompt_version,
        'content', v_activity.content
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_ai_learning_activity(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_learning_activity(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.record_ai_practice_response(
    p_student_id uuid,
    p_activity_id uuid,
    p_item_id uuid,
    p_submitted_answer jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_activity private.ai_learning_activities%ROWTYPE;
    v_item jsonb;
    v_correct boolean;
    v_response_id uuid;
BEGIN
    SELECT activity.* INTO v_activity
    FROM private.ai_learning_activities AS activity
    WHERE activity.id = p_activity_id
      AND activity.student_id = p_student_id
      AND activity.activity_type = 'practice';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Practice activity is unavailable' USING ERRCODE = '42501';
    END IF;
    IF CASE
        WHEN pg_catalog.jsonb_typeof(p_submitted_answer) = 'object' THEN
            (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(p_submitted_answer)) <> 1
            OR pg_catalog.jsonb_typeof(p_submitted_answer->'selected_option') IS DISTINCT FROM 'string'
        ELSE true
    END THEN
        RAISE EXCEPTION 'Practice answer shape is invalid' USING ERRCODE = '22023';
    END IF;

    SELECT entry.item INTO v_item
    FROM pg_catalog.jsonb_array_elements(v_activity.content->'items') AS entry(item)
    WHERE entry.item->>'id' = p_item_id::text;
    IF v_item IS NULL THEN
        RAISE EXCEPTION 'Practice item is not part of the activity' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.jsonb_array_elements(v_item->'answer_choices') AS choice(value)
        WHERE choice.value->>'id' = p_submitted_answer->>'selected_option'
    ) THEN
        RAISE EXCEPTION 'Selected option is not valid for this item' USING ERRCODE = '22023';
    END IF;
    v_correct := v_item->'correct_answer'->>'selected_option' = p_submitted_answer->>'selected_option';

    INSERT INTO private.ai_practice_responses (
        student_id, activity_id, item_id, submitted_answer, is_correct
    ) VALUES (
        p_student_id, p_activity_id, p_item_id, p_submitted_answer, v_correct
    ) RETURNING id INTO v_response_id;

    RETURN pg_catalog.jsonb_build_object('id', v_response_id, 'is_correct', v_correct);
END;
$$;
REVOKE ALL ON FUNCTION public.record_ai_practice_response(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_practice_response(uuid, uuid, uuid, jsonb) TO service_role;

COMMIT;
