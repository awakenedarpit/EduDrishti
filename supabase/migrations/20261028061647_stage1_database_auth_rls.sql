-- Stage 1: EduDrishti database, Auth provisioning, and row-level security.
-- Additive migration: creates new application objects; it does not drop or alter
-- existing application data or Supabase-managed auth objects.
BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE public.profiles (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    app_role text NOT NULL DEFAULT 'student'
        CHECK (app_role IN ('student', 'teacher')),
    display_name text CHECK (display_name IS NULL OR char_length(display_name) <= 100),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.classes (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    teacher_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (char_length(pg_catalog.btrim(name)) BETWEEN 1 AND 120),
    grade_level smallint NOT NULL CHECK (grade_level BETWEEN 1 AND 12),
    subject text NOT NULL CHECK (char_length(pg_catalog.btrim(subject)) BETWEEN 1 AND 80),
    description text CHECK (description IS NULL OR char_length(description) <= 1000),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT classes_teacher_name_unique UNIQUE (teacher_id, name)
);

CREATE TABLE public.enrollments (
    class_id uuid NOT NULL REFERENCES public.classes (id) ON DELETE RESTRICT,
    student_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
    enrolled_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    created_by_teacher_id uuid REFERENCES public.profiles (user_id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    PRIMARY KEY (class_id, student_id)
);

CREATE TABLE public.topics (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    subject text NOT NULL CHECK (char_length(pg_catalog.btrim(subject)) BETWEEN 1 AND 80),
    grade_level smallint NOT NULL CHECK (grade_level BETWEEN 1 AND 12),
    code text NOT NULL CHECK (code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    title text NOT NULL CHECK (char_length(pg_catalog.btrim(title)) BETWEEN 1 AND 160),
    description text CHECK (description IS NULL OR char_length(description) <= 2000),
    parent_topic_id uuid REFERENCES public.topics (id) ON DELETE SET NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_catalog.jsonb_typeof(metadata) = 'object'),
    is_published boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT topics_subject_grade_code_unique UNIQUE (subject, grade_level, code)
);

CREATE TABLE public.questions (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    author_teacher_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE RESTRICT,
    topic_id uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
    question_type text NOT NULL CHECK (
        question_type IN ('single_choice', 'multiple_choice', 'numeric', 'short_text')
    ),
    prompt text NOT NULL CHECK (char_length(pg_catalog.btrim(prompt)) BETWEEN 1 AND 10000),
    options jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (pg_catalog.jsonb_typeof(options) = 'array'),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

-- Answer keys and grading configuration are deliberately separate from question
-- content so a student who can read an assigned question cannot read its solution.
CREATE TABLE public.question_answer_keys (
    question_id uuid PRIMARY KEY REFERENCES public.questions (id) ON DELETE CASCADE,
    answer_config jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(answer_config) = 'object'),
    grading_config jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (pg_catalog.jsonb_typeof(grading_config) = 'object'),
    rationale text CHECK (rationale IS NULL OR char_length(rationale) <= 10000),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.assessments (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    class_id uuid NOT NULL REFERENCES public.classes (id) ON DELETE RESTRICT,
    created_by_teacher_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE RESTRICT,
    title text NOT NULL CHECK (char_length(pg_catalog.btrim(title)) BETWEEN 1 AND 200),
    description text CHECK (description IS NULL OR char_length(description) <= 4000),
    assessment_type text NOT NULL DEFAULT 'diagnostic'
        CHECK (assessment_type IN ('diagnostic', 'practice', 'summative')),
    status text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'published', 'archived')),
    opens_at timestamptz,
    closes_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT assessments_window_check CHECK (
        opens_at IS NULL OR closes_at IS NULL OR closes_at > opens_at
    )
);

-- A normalized many-to-many relation allows question reuse while preserving each
-- assessment's order and point value.
CREATE TABLE public.assessment_questions (
    assessment_id uuid NOT NULL REFERENCES public.assessments (id) ON DELETE RESTRICT,
    question_id uuid NOT NULL REFERENCES public.questions (id) ON DELETE RESTRICT,
    position integer NOT NULL CHECK (position > 0),
    points numeric(7, 2) NOT NULL DEFAULT 1 CHECK (points > 0),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    PRIMARY KEY (assessment_id, question_id),
    CONSTRAINT assessment_questions_position_unique UNIQUE (assessment_id, position)
);

CREATE TABLE public.assessment_attempts (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    assessment_id uuid NOT NULL REFERENCES public.assessments (id) ON DELETE RESTRICT,
    student_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
    attempt_number integer NOT NULL CHECK (attempt_number > 0),
    status text NOT NULL DEFAULT 'in_progress'
        CHECK (status IN ('in_progress', 'submitted', 'graded', 'abandoned')),
    started_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    submitted_at timestamptz,
    score_percent numeric(5, 2) CHECK (score_percent IS NULL OR score_percent BETWEEN 0 AND 100),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT assessment_attempt_number_unique
        UNIQUE (assessment_id, student_id, attempt_number),
    CONSTRAINT assessment_attempt_submission_check CHECK (
        (status = 'in_progress' AND submitted_at IS NULL)
        OR (status IN ('submitted', 'graded') AND submitted_at IS NOT NULL)
        OR status = 'abandoned'
    ),
    CONSTRAINT assessment_attempt_score_check CHECK (
        status = 'graded' OR score_percent IS NULL
    ),
    CONSTRAINT assessment_attempt_id_assessment_unique UNIQUE (id, assessment_id)
);

CREATE UNIQUE INDEX assessment_attempts_one_in_progress_idx
    ON public.assessment_attempts (assessment_id, student_id)
    WHERE status = 'in_progress';

CREATE TABLE public.responses (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    attempt_id uuid NOT NULL,
    assessment_id uuid NOT NULL,
    question_id uuid NOT NULL,
    answer jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(answer) = 'object'),
    answered_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    score_percent numeric(5, 2) CHECK (score_percent IS NULL OR score_percent BETWEEN 0 AND 100),
    is_correct boolean,
    feedback jsonb CHECK (feedback IS NULL OR pg_catalog.jsonb_typeof(feedback) = 'object'),
    graded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT responses_attempt_question_unique UNIQUE (attempt_id, question_id),
    CONSTRAINT responses_attempt_assessment_fk
        FOREIGN KEY (attempt_id, assessment_id)
        REFERENCES public.assessment_attempts (id, assessment_id) ON DELETE CASCADE,
    CONSTRAINT responses_assessment_question_fk
        FOREIGN KEY (assessment_id, question_id)
        REFERENCES public.assessment_questions (assessment_id, question_id) ON DELETE RESTRICT,
    CONSTRAINT responses_grading_fields_check CHECK (
        (graded_at IS NULL AND score_percent IS NULL AND is_correct IS NULL)
        OR (graded_at IS NOT NULL AND score_percent IS NOT NULL)
    )
);

CREATE TABLE public.diagnoses (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    source_attempt_id uuid NOT NULL REFERENCES public.assessment_attempts (id) ON DELETE CASCADE,
    topic_id uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
    misconception_code text NOT NULL
        CHECK (misconception_code ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
    summary text NOT NULL CHECK (char_length(pg_catalog.btrim(summary)) BETWEEN 1 AND 2000),
    evidence jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(evidence) = 'object'),
    confidence numeric(4, 3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT diagnoses_attempt_topic_code_unique
        UNIQUE (source_attempt_id, topic_id, misconception_code)
);

CREATE TABLE public.learning_sessions (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    class_id uuid NOT NULL,
    student_id uuid NOT NULL,
    topic_id uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
    activity_type text NOT NULL
        CHECK (activity_type IN ('explanation', 'practice', 'review', 'diagnostic')),
    started_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    ended_at timestamptz,
    details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_catalog.jsonb_typeof(details) = 'object'),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT learning_sessions_time_check CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT learning_sessions_enrollment_fk
        FOREIGN KEY (class_id, student_id)
        REFERENCES public.enrollments (class_id, student_id) ON DELETE CASCADE
);

-- Progress is stored as dated observations rather than one mutable mastery value,
-- preserving the evidence trail while avoiding duplicated learner/topic summaries.
CREATE TABLE public.progress_records (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    class_id uuid NOT NULL,
    student_id uuid NOT NULL,
    topic_id uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
    mastery_score numeric(5, 4) NOT NULL CHECK (mastery_score BETWEEN 0 AND 1),
    evidence_count integer NOT NULL DEFAULT 1 CHECK (evidence_count >= 0),
    basis text NOT NULL CHECK (basis IN ('assessment', 'practice', 'teacher_review', 'diagnostic')),
    recorded_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT progress_records_enrollment_fk
        FOREIGN KEY (class_id, student_id)
        REFERENCES public.enrollments (class_id, student_id) ON DELETE CASCADE
);

CREATE INDEX classes_teacher_created_idx ON public.classes (teacher_id, created_at DESC);
CREATE INDEX enrollments_student_status_idx ON public.enrollments (student_id, status, class_id);
CREATE INDEX topics_parent_idx ON public.topics (parent_topic_id) WHERE parent_topic_id IS NOT NULL;
CREATE INDEX questions_author_topic_idx ON public.questions (author_teacher_id, topic_id);
CREATE INDEX assessments_class_status_idx ON public.assessments (class_id, status, opens_at);
CREATE INDEX assessment_questions_question_idx ON public.assessment_questions (question_id, assessment_id);
CREATE INDEX assessment_attempts_student_status_idx
    ON public.assessment_attempts (student_id, status, started_at DESC);
CREATE INDEX assessment_attempts_assessment_status_idx
    ON public.assessment_attempts (assessment_id, status, started_at DESC);
CREATE INDEX responses_assessment_question_idx ON public.responses (assessment_id, question_id);
CREATE INDEX diagnoses_topic_created_idx ON public.diagnoses (topic_id, created_at DESC);
CREATE INDEX learning_sessions_student_started_idx
    ON public.learning_sessions (student_id, started_at DESC);
CREATE INDEX learning_sessions_class_topic_idx
    ON public.learning_sessions (class_id, topic_id, started_at DESC);
CREATE INDEX progress_student_topic_recorded_idx
    ON public.progress_records (student_id, topic_id, recorded_at DESC);
CREATE INDEX progress_class_recorded_idx
    ON public.progress_records (class_id, recorded_at DESC);

CREATE FUNCTION private.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := pg_catalog.now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER classes_set_updated_at BEFORE UPDATE ON public.classes
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER enrollments_set_updated_at BEFORE UPDATE ON public.enrollments
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER topics_set_updated_at BEFORE UPDATE ON public.topics
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER questions_set_updated_at BEFORE UPDATE ON public.questions
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER question_answer_keys_set_updated_at BEFORE UPDATE ON public.question_answer_keys
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER assessments_set_updated_at BEFORE UPDATE ON public.assessments
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER assessment_attempts_set_updated_at BEFORE UPDATE ON public.assessment_attempts
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER responses_set_updated_at BEFORE UPDATE ON public.responses
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

-- Auth metadata is untrusted: role is always set to student, regardless of any
-- client-supplied user_metadata.role or app_role value.
CREATE FUNCTION private.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (user_id, app_role, display_name)
    VALUES (
        NEW.id,
        'student',
        NULLIF(
            pg_catalog.left(
                pg_catalog.btrim(
                    COALESCE(NEW.raw_user_meta_data, '{}'::jsonb) ->> 'display_name'
                ),
                100
            ),
            ''
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION private.handle_new_auth_user();

CREATE FUNCTION private.is_current_user_teacher()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.user_id = (SELECT auth.uid())
          AND p.app_role = 'teacher'
    );
$$;

CREATE FUNCTION private.owns_class(p_class_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.classes AS c
        JOIN public.profiles AS p ON p.user_id = c.teacher_id
        WHERE c.id = p_class_id
          AND c.teacher_id = (SELECT auth.uid())
          AND p.app_role = 'teacher'
    );
$$;

CREATE FUNCTION private.is_active_student_in_class(p_class_id uuid, p_student_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.enrollments AS e
        WHERE e.class_id = p_class_id
          AND e.student_id = p_student_id
          AND e.status = 'active'
    );
$$;

CREATE FUNCTION private.can_teacher_view_student(p_student_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles AS student_profile
        JOIN public.enrollments AS e ON e.student_id = student_profile.user_id
        JOIN public.classes AS c ON c.id = e.class_id
        JOIN public.profiles AS teacher_profile ON teacher_profile.user_id = c.teacher_id
        WHERE student_profile.user_id = p_student_id
          AND student_profile.app_role = 'student'
          AND teacher_profile.user_id = (SELECT auth.uid())
          AND teacher_profile.app_role = 'teacher'
    );
$$;

CREATE FUNCTION private.can_view_class(p_class_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.owns_class(p_class_id)
        OR private.is_active_student_in_class(p_class_id, (SELECT auth.uid()));
$$;

CREATE FUNCTION private.can_view_assessment(p_assessment_id uuid)
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
                  a.status = 'published'
                  AND private.is_active_student_in_class(a.class_id, (SELECT auth.uid()))
              )
          )
    );
$$;

CREATE FUNCTION private.is_question_author(p_question_id uuid)
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
          AND q.author_teacher_id = (SELECT auth.uid())
          AND private.is_current_user_teacher()
    );
$$;

CREATE FUNCTION private.can_view_question(p_question_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.is_question_author(p_question_id)
        OR EXISTS (
            SELECT 1
            FROM public.assessment_questions AS aq
            JOIN public.assessments AS a ON a.id = aq.assessment_id
            WHERE aq.question_id = p_question_id
              AND private.can_view_assessment(a.id)
        );
$$;

CREATE FUNCTION private.can_manage_assessment(p_assessment_id uuid)
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
          AND a.created_by_teacher_id = (SELECT auth.uid())
          AND private.owns_class(a.class_id)
          AND a.status = 'draft'
          AND NOT EXISTS (
              SELECT 1
              FROM public.assessment_attempts AS aa
              WHERE aa.assessment_id = a.id
          )
    );
$$;

CREATE FUNCTION private.can_manage_question(p_question_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT private.is_question_author(p_question_id)
        AND NOT EXISTS (
            SELECT 1
            FROM public.assessment_questions AS aq
            JOIN public.assessments AS a ON a.id = aq.assessment_id
            WHERE aq.question_id = p_question_id
              AND (
                  a.status <> 'draft'
                  OR EXISTS (
                      SELECT 1
                      FROM public.assessment_attempts AS aa
                      WHERE aa.assessment_id = a.id
                  )
              )
        );
$$;

CREATE FUNCTION private.can_view_attempt(p_attempt_id uuid)
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
              OR private.owns_class(a.class_id)
          )
    );
$$;

-- These RPCs set ownership from the verified JWT identity. Clients cannot insert
-- classes, enrollments, attempts, responses, diagnoses, sessions, or progress rows.
CREATE FUNCTION public.create_class(
    p_name text,
    p_grade_level smallint,
    p_subject text,
    p_description text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_class_id uuid;
BEGIN
    IF (SELECT auth.uid()) IS NULL OR NOT private.is_current_user_teacher() THEN
        RAISE EXCEPTION 'A trusted teacher profile is required to create a class'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.classes (teacher_id, name, grade_level, subject, description)
    VALUES ((SELECT auth.uid()), p_name, p_grade_level, p_subject, p_description)
    RETURNING id INTO v_class_id;

    RETURN v_class_id;
END;
$$;

CREATE FUNCTION public.enroll_student(p_class_id uuid, p_student_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (SELECT auth.uid()) IS NULL OR NOT private.owns_class(p_class_id) THEN
        RAISE EXCEPTION 'Only the owning teacher can enroll a student'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.user_id = p_student_id
          AND p.app_role = 'student'
    ) THEN
        RAISE EXCEPTION 'The target account is not a student'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.enrollments (class_id, student_id, status, created_by_teacher_id)
    VALUES (p_class_id, p_student_id, 'active', (SELECT auth.uid()))
    ON CONFLICT (class_id, student_id) DO UPDATE
        SET status = 'active',
            enrolled_at = pg_catalog.now(),
            created_by_teacher_id = (SELECT auth.uid());
END;
$$;

CREATE FUNCTION public.start_assessment(p_assessment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := (SELECT auth.uid());
    v_class_id uuid;
    v_attempt_id uuid;
    v_attempt_number integer;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles AS p
        WHERE p.user_id = v_user_id AND p.app_role = 'student'
    ) THEN
        RAISE EXCEPTION 'A student profile is required to start an assessment'
            USING ERRCODE = '42501';
    END IF;

    SELECT a.class_id INTO v_class_id
    FROM public.assessments AS a
    WHERE a.id = p_assessment_id
      AND a.status = 'published'
      AND (a.opens_at IS NULL OR a.opens_at <= pg_catalog.now())
      AND (a.closes_at IS NULL OR a.closes_at > pg_catalog.now());

    IF v_class_id IS NULL THEN
        RAISE EXCEPTION 'Assessment is not available' USING ERRCODE = '22023';
    END IF;

    IF NOT private.is_active_student_in_class(v_class_id, v_user_id) THEN
        RAISE EXCEPTION 'An active class enrollment is required'
            USING ERRCODE = '42501';
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

    SELECT COALESCE(pg_catalog.max(aa.attempt_number), 0) + 1
    INTO v_attempt_number
    FROM public.assessment_attempts AS aa
    WHERE aa.assessment_id = p_assessment_id
      AND aa.student_id = v_user_id;

    INSERT INTO public.assessment_attempts (assessment_id, student_id, attempt_number)
    VALUES (p_assessment_id, v_user_id, v_attempt_number)
    RETURNING id INTO v_attempt_id;

    RETURN v_attempt_id;
END;
$$;

CREATE FUNCTION public.save_response(
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
    v_response_id uuid;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;

    IF p_answer IS NULL
       OR pg_catalog.jsonb_typeof(p_answer) <> 'object'
       OR pg_catalog.pg_column_size(p_answer) > 16384 THEN
        RAISE EXCEPTION 'Answer must be a JSON object no larger than 16 KiB'
            USING ERRCODE = '22023';
    END IF;

    SELECT aa.assessment_id, aa.status
    INTO v_assessment_id, v_status
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id
      AND aa.student_id = (SELECT auth.uid())
    FOR UPDATE;

    IF v_assessment_id IS NULL THEN
        RAISE EXCEPTION 'Attempt not found for current student' USING ERRCODE = '42501';
    END IF;

    IF v_status <> 'in_progress' THEN
        RAISE EXCEPTION 'Responses can only be changed in an active attempt'
            USING ERRCODE = '55000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.assessment_questions AS aq
        WHERE aq.assessment_id = v_assessment_id
          AND aq.question_id = p_question_id
    ) THEN
        RAISE EXCEPTION 'Question is not part of this assessment' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.responses (attempt_id, assessment_id, question_id, answer)
    VALUES (p_attempt_id, v_assessment_id, p_question_id, p_answer)
    ON CONFLICT (attempt_id, question_id) DO UPDATE
        SET answer = EXCLUDED.answer,
            answered_at = pg_catalog.now()
        WHERE public.responses.graded_at IS NULL
          AND public.responses.score_percent IS NULL
    RETURNING id INTO v_response_id;

    IF v_response_id IS NULL THEN
        RAISE EXCEPTION 'A graded response cannot be overwritten' USING ERRCODE = '55000';
    END IF;

    RETURN v_response_id;
END;
$$;

CREATE FUNCTION public.submit_assessment(p_attempt_id uuid)
RETURNS void
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

    SELECT aa.status INTO v_status
    FROM public.assessment_attempts AS aa
    WHERE aa.id = p_attempt_id
      AND aa.student_id = (SELECT auth.uid())
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Attempt not found for current student' USING ERRCODE = '42501';
    END IF;

    IF v_status <> 'in_progress' THEN
        RAISE EXCEPTION 'Only an active attempt can be submitted' USING ERRCODE = '55000';
    END IF;

    UPDATE public.assessment_attempts
    SET status = 'submitted', submitted_at = pg_catalog.now()
    WHERE id = p_attempt_id;
END;
$$;

-- The initial Quadratic Equations topic is public educational metadata, not learner data.
INSERT INTO public.topics (subject, grade_level, code, title, description, metadata, is_published)
VALUES (
    'Mathematics',
    10,
    'quadratic-equations',
    'Quadratic Equations',
    'Class 10 concepts and learning objectives for quadratic equations.',
    '{"curriculum_level":"Class 10"}'::jsonb,
    true
)
ON CONFLICT (subject, grade_level, code) DO NOTHING;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.question_answer_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress_records ENABLE ROW LEVEL SECURITY;

-- Revoke Supabase's possible default public/authenticated grants first, then add
-- only the precise client operations required. service_role stays server-only.
REVOKE ALL ON TABLE
    public.profiles, public.classes, public.enrollments, public.topics,
    public.questions, public.question_answer_keys, public.assessments,
    public.assessment_questions, public.assessment_attempts, public.responses,
    public.diagnoses, public.learning_sessions, public.progress_records
FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE
    public.profiles, public.classes, public.enrollments, public.topics,
    public.questions, public.question_answer_keys, public.assessments,
    public.assessment_questions, public.assessment_attempts, public.responses,
    public.diagnoses, public.learning_sessions, public.progress_records
TO service_role;

GRANT SELECT ON public.profiles, public.classes, public.enrollments TO authenticated;
GRANT UPDATE (display_name) ON public.profiles TO authenticated;
GRANT UPDATE (name, grade_level, subject, description) ON public.classes TO authenticated;
GRANT UPDATE (status) ON public.enrollments TO authenticated;
GRANT SELECT ON public.topics TO anon, authenticated;
GRANT SELECT, INSERT ON public.questions TO authenticated;
GRANT UPDATE (topic_id, question_type, prompt, options, is_active) ON public.questions TO authenticated;
GRANT SELECT, INSERT ON public.question_answer_keys TO authenticated;
GRANT UPDATE (answer_config, grading_config, rationale) ON public.question_answer_keys TO authenticated;
GRANT SELECT, INSERT ON public.assessments TO authenticated;
GRANT UPDATE (title, description, assessment_type, status, opens_at, closes_at)
    ON public.assessments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.assessment_questions TO authenticated;
GRANT SELECT ON public.assessment_attempts, public.responses, public.diagnoses,
    public.learning_sessions, public.progress_records TO authenticated;

CREATE POLICY profiles_select_self
    ON public.profiles FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));
CREATE POLICY profiles_teacher_select_enrolled_students
    ON public.profiles FOR SELECT TO authenticated
    USING (private.can_teacher_view_student(user_id));
CREATE POLICY profiles_update_self_display_name
    ON public.profiles FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY classes_select_authorized
    ON public.classes FOR SELECT TO authenticated
    USING (private.can_view_class(id));
CREATE POLICY classes_update_owner
    ON public.classes FOR UPDATE TO authenticated
    USING (private.owns_class(id))
    WITH CHECK (private.owns_class(id));

CREATE POLICY enrollments_select_student_or_owner
    ON public.enrollments FOR SELECT TO authenticated
    USING (student_id = (SELECT auth.uid()) OR private.owns_class(class_id));
CREATE POLICY enrollments_update_owner
    ON public.enrollments FOR UPDATE TO authenticated
    USING (private.owns_class(class_id))
    WITH CHECK (private.owns_class(class_id));

CREATE POLICY topics_select_published
    ON public.topics FOR SELECT TO anon, authenticated
    USING (is_published);

CREATE POLICY questions_select_assigned_or_authored
    ON public.questions FOR SELECT TO authenticated
    USING (private.can_view_question(id));
CREATE POLICY questions_insert_teacher_authored
    ON public.questions FOR INSERT TO authenticated
    WITH CHECK (
        author_teacher_id = (SELECT auth.uid())
        AND private.is_current_user_teacher()
        AND EXISTS (
            SELECT 1 FROM public.topics AS t
            WHERE t.id = topic_id AND t.is_published
        )
    );
CREATE POLICY questions_update_draft_author
    ON public.questions FOR UPDATE TO authenticated
    USING (private.can_manage_question(id))
    WITH CHECK (private.is_question_author(id));

CREATE POLICY question_answer_keys_select_author
    ON public.question_answer_keys FOR SELECT TO authenticated
    USING (private.is_question_author(question_id));
CREATE POLICY question_answer_keys_insert_author
    ON public.question_answer_keys FOR INSERT TO authenticated
    WITH CHECK (private.can_manage_question(question_id));
CREATE POLICY question_answer_keys_update_author
    ON public.question_answer_keys FOR UPDATE TO authenticated
    USING (private.can_manage_question(question_id))
    WITH CHECK (private.can_manage_question(question_id));

CREATE POLICY assessments_select_authorized
    ON public.assessments FOR SELECT TO authenticated
    USING (private.can_view_assessment(id));
CREATE POLICY assessments_insert_teacher_owned_class
    ON public.assessments FOR INSERT TO authenticated
    WITH CHECK (
        created_by_teacher_id = (SELECT auth.uid())
        AND private.owns_class(class_id)
        AND status = 'draft'
    );
CREATE POLICY assessments_update_unstarted_draft
    ON public.assessments FOR UPDATE TO authenticated
    USING (private.can_manage_assessment(id))
    WITH CHECK (
        created_by_teacher_id = (SELECT auth.uid())
        AND private.owns_class(class_id)
        AND status IN ('draft', 'published')
    );

CREATE POLICY assessment_questions_select_authorized
    ON public.assessment_questions FOR SELECT TO authenticated
    USING (private.can_view_assessment(assessment_id));
CREATE POLICY assessment_questions_insert_teacher_draft
    ON public.assessment_questions FOR INSERT TO authenticated
    WITH CHECK (
        private.can_manage_assessment(assessment_id)
        AND private.can_manage_question(question_id)
    );
CREATE POLICY assessment_questions_update_teacher_draft
    ON public.assessment_questions FOR UPDATE TO authenticated
    USING (
        private.can_manage_assessment(assessment_id)
        AND private.can_manage_question(question_id)
    )
    WITH CHECK (
        private.can_manage_assessment(assessment_id)
        AND private.can_manage_question(question_id)
    );
CREATE POLICY assessment_questions_delete_teacher_draft
    ON public.assessment_questions FOR DELETE TO authenticated
    USING (private.can_manage_assessment(assessment_id));

CREATE POLICY assessment_attempts_select_student_or_class_teacher
    ON public.assessment_attempts FOR SELECT TO authenticated
    USING (private.can_view_attempt(id));
CREATE POLICY responses_select_student_or_class_teacher
    ON public.responses FOR SELECT TO authenticated
    USING (private.can_view_attempt(attempt_id));
CREATE POLICY diagnoses_select_student_or_class_teacher
    ON public.diagnoses FOR SELECT TO authenticated
    USING (private.can_view_attempt(source_attempt_id));

CREATE POLICY learning_sessions_select_student_or_class_teacher
    ON public.learning_sessions FOR SELECT TO authenticated
    USING (student_id = (SELECT auth.uid()) OR private.owns_class(class_id));
CREATE POLICY progress_records_select_student_or_class_teacher
    ON public.progress_records FOR SELECT TO authenticated
    USING (student_id = (SELECT auth.uid()) OR private.owns_class(class_id));

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_current_user_teacher() TO authenticated;
GRANT EXECUTE ON FUNCTION private.owns_class(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_active_student_in_class(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_teacher_view_student(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_class(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_question_author(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_question(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_question(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_attempt(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_class(text, smallint, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.enroll_student(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_assessment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_response(uuid, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_assessment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_class(text, smallint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enroll_student(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_response(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assessment(uuid) TO authenticated;

COMMIT;
