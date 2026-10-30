-- Stage 5: persistent, versioned learning progress and mastery.
-- Progress is derived from immutable graded assessment responses and completed
-- targeted-practice activities. Diagnosis signals are reported separately and
-- never increase or decrease the mastery score.
BEGIN;

ALTER TABLE public.progress_records
    ALTER COLUMN class_id DROP NOT NULL,
    ALTER COLUMN mastery_score DROP NOT NULL,
    ADD COLUMN learning_objective text NOT NULL DEFAULT 'topic_overall',
    ADD COLUMN is_topic_summary boolean NOT NULL DEFAULT false,
    ADD COLUMN calculation_version text NOT NULL DEFAULT 'legacy',
    ADD COLUMN mastery_status text NOT NULL DEFAULT 'legacy_unversioned',
    ADD COLUMN evidence_through timestamptz,
    ADD COLUMN evidence_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN source_event_type text,
    ADD COLUMN source_event_id uuid,
    ADD CONSTRAINT progress_records_objective_check
        CHECK (char_length(pg_catalog.btrim(learning_objective)) BETWEEN 1 AND 100),
    ADD CONSTRAINT progress_records_calculation_version_check
        CHECK (calculation_version ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    ADD CONSTRAINT progress_records_mastery_status_check
        CHECK (mastery_status IN ('insufficient_evidence', 'emerging', 'developing', 'secure', 'legacy_unversioned')),
    ADD CONSTRAINT progress_records_mastery_status_score_check
        CHECK (
            (mastery_status = 'insufficient_evidence' AND mastery_score IS NULL)
            OR (mastery_status <> 'insufficient_evidence' AND mastery_score IS NOT NULL)
        ),
    ADD CONSTRAINT progress_records_evidence_summary_check
        CHECK (pg_catalog.jsonb_typeof(evidence_summary) = 'object'),
    ADD CONSTRAINT progress_records_source_event_pair_check
        CHECK (
            ((source_event_type IS NULL) = (source_event_id IS NULL))
            AND (source_event_type IS NULL OR source_event_type IN ('assessment_attempt', 'practice_response'))
        );

ALTER TABLE public.progress_records
    DROP CONSTRAINT IF EXISTS progress_records_basis_check,
    ADD CONSTRAINT progress_records_basis_check
        CHECK (basis IN ('assessment', 'practice', 'combined', 'teacher_review', 'diagnostic'));

CREATE INDEX progress_records_model_history_idx
    ON public.progress_records (student_id, topic_id, calculation_version, evidence_through DESC);
CREATE UNIQUE INDEX progress_records_source_snapshot_unique_idx
    ON public.progress_records (
        source_event_type, source_event_id, student_id, topic_id,
        learning_objective, is_topic_summary, calculation_version
    )
    WHERE source_event_type IS NOT NULL AND source_event_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.learning_recency_weight(
    p_observed_at timestamptz,
    p_as_of timestamptz
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN p_observed_at IS NULL OR p_as_of IS NULL THEN 0::numeric
        WHEN p_observed_at >= p_as_of THEN 1::numeric
        ELSE pg_catalog.power(
            0.5::numeric,
            GREATEST(
                0::numeric,
                EXTRACT(EPOCH FROM (p_as_of - p_observed_at))::numeric / 86400::numeric / 90::numeric
            )
        )
    END;
$$;

CREATE OR REPLACE FUNCTION private.learning_mastery_status(
    p_evidence_units integer,
    p_evidence_days integer,
    p_latest_evidence timestamptz,
    p_as_of timestamptz,
    p_weighted_accuracy numeric
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN p_evidence_units IS NULL OR p_evidence_units < 5
          OR p_evidence_days IS NULL OR p_evidence_days < 2
          OR p_latest_evidence IS NULL OR p_as_of IS NULL
          OR p_latest_evidence < p_as_of - INTERVAL '90 days'
          OR p_weighted_accuracy IS NULL
        THEN 'insufficient_evidence'
        WHEN p_weighted_accuracy >= 0.80 THEN 'secure'
        WHEN p_weighted_accuracy >= 0.60 THEN 'developing'
        ELSE 'emerging'
    END;
$$;

CREATE OR REPLACE FUNCTION private.learning_progress_evidence(
    p_student_id uuid,
    p_class_id uuid,
    p_through timestamptz
)
RETURNS TABLE (
    student_id uuid,
    topic_id uuid,
    topic_title text,
    topic_code text,
    subject text,
    grade_level smallint,
    learning_objective text,
    evidence_type text,
    evidence_id uuid,
    attempt_id uuid,
    observed_at timestamptz,
    score numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH assessment_evidence AS (
        SELECT aa.student_id,
               t.id AS topic_id,
               t.title AS topic_title,
               t.code AS topic_code,
               t.subject,
               t.grade_level,
               COALESCE(q.concept, 'unclassified') AS learning_objective,
               'assessment_item'::text AS evidence_type,
               r.id AS evidence_id,
               aa.id AS attempt_id,
               COALESCE(r.graded_at, aa.submitted_at, r.answered_at) AS observed_at,
               CASE WHEN r.is_correct THEN 1::numeric ELSE 0::numeric END AS score
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        JOIN public.responses AS r ON r.attempt_id = aa.id AND r.assessment_id = aa.assessment_id
        JOIN public.questions AS q ON q.id = r.question_id
        JOIN public.topics AS t ON t.id = q.topic_id
        WHERE aa.status = 'graded'
          AND r.is_answered
          AND r.is_correct IS NOT NULL
          AND COALESCE(r.graded_at, aa.submitted_at, r.answered_at) <= p_through
          AND (
              (p_class_id IS NULL AND p_student_id IS NOT NULL AND aa.student_id = p_student_id)
              OR (
                  p_class_id IS NOT NULL
                  AND a.class_id = p_class_id
                  AND (p_student_id IS NULL OR aa.student_id = p_student_id)
                  AND EXISTS (
                      SELECT 1 FROM public.enrollments AS e
                      WHERE e.class_id = p_class_id
                        AND e.student_id = aa.student_id
                        AND e.status = 'active'
                  )
              )
          )
    ),
    practice_items AS (
        SELECT activity.student_id,
               t.id AS topic_id,
               t.title AS topic_title,
               t.code AS topic_code,
               t.subject,
               t.grade_level,
               COALESCE(q.concept, 'unclassified') AS learning_objective,
               activity.id AS activity_id,
               activity.attempt_id,
               item.value->>'id' AS item_key
        FROM private.ai_learning_activities AS activity
        JOIN public.assessment_attempts AS aa ON aa.id = activity.attempt_id
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        JOIN public.questions AS q ON q.id = activity.question_id
        JOIN public.topics AS t ON t.id = q.topic_id
        CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(
            CASE
                WHEN pg_catalog.jsonb_typeof(activity.content->'items') = 'array'
                    THEN activity.content->'items'
                ELSE '[]'::jsonb
            END
        ) AS item(value)
        WHERE activity.activity_type = 'practice'
          AND aa.status = 'graded'
          AND activity.created_at <= p_through
          AND (
              (p_class_id IS NULL AND p_student_id IS NOT NULL AND activity.student_id = p_student_id)
              OR (
                  p_class_id IS NOT NULL
                  AND a.class_id = p_class_id
                  AND (p_student_id IS NULL OR activity.student_id = p_student_id)
                  AND EXISTS (
                      SELECT 1 FROM public.enrollments AS e
                      WHERE e.class_id = p_class_id
                        AND e.student_id = activity.student_id
                        AND e.status = 'active'
                  )
              )
          )
    ),
    latest_practice_answers AS (
        SELECT DISTINCT ON (response.activity_id, response.item_id)
               response.activity_id,
               response.item_id,
               response.is_correct,
               response.created_at
        FROM private.ai_practice_responses AS response
        JOIN (SELECT DISTINCT activity_id, item_key FROM practice_items) AS allowed
          ON allowed.activity_id = response.activity_id
         AND allowed.item_key = response.item_id::text
        WHERE response.created_at <= p_through
        ORDER BY response.activity_id, response.item_id, response.created_at DESC, response.id DESC
    ),
    completed_practice AS (
        SELECT item.student_id,
               item.topic_id,
               item.topic_title,
               item.topic_code,
               item.subject,
               item.grade_level,
               item.learning_objective,
               'practice_activity'::text AS evidence_type,
               item.activity_id AS evidence_id,
               item.attempt_id,
               pg_catalog.max(answer.created_at) AS observed_at,
               pg_catalog.avg(CASE WHEN answer.is_correct THEN 1::numeric ELSE 0::numeric END) AS score,
               pg_catalog.count(item.item_key) AS item_count,
               pg_catalog.count(answer.item_id) AS answered_count
        FROM practice_items AS item
        LEFT JOIN latest_practice_answers AS answer
          ON answer.activity_id = item.activity_id
         AND answer.item_id::text = item.item_key
        GROUP BY item.student_id, item.topic_id, item.topic_title, item.topic_code,
                 item.subject, item.grade_level, item.learning_objective,
                 item.activity_id, item.attempt_id
        HAVING pg_catalog.count(item.item_key) = pg_catalog.count(answer.item_id)
    )
    SELECT assessment.student_id, assessment.topic_id, assessment.topic_title,
           assessment.topic_code, assessment.subject, assessment.grade_level,
           assessment.learning_objective, assessment.evidence_type,
           assessment.evidence_id, assessment.attempt_id, assessment.observed_at,
           assessment.score
    FROM assessment_evidence AS assessment
    UNION ALL
    SELECT practice.student_id, practice.topic_id, practice.topic_title,
           practice.topic_code, practice.subject, practice.grade_level,
           practice.learning_objective, practice.evidence_type,
           practice.evidence_id, practice.attempt_id, practice.observed_at,
           practice.score
    FROM completed_practice AS practice
    WHERE practice.item_count > 0;
$$;

CREATE OR REPLACE FUNCTION private.learning_progress_diagnoses(
    p_student_id uuid,
    p_class_id uuid,
    p_through timestamptz
)
RETURNS TABLE (
    student_id uuid,
    topic_id uuid,
    learning_objective text,
    diagnosis_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT aa.student_id,
           diagnosis.topic_id,
           COALESCE(question.concept, 'unclassified') AS learning_objective,
           pg_catalog.count(DISTINCT diagnosis.id)::integer AS diagnosis_count
    FROM public.diagnoses AS diagnosis
    JOIN public.assessment_attempts AS aa ON aa.id = diagnosis.source_attempt_id
    JOIN public.assessments AS assessment ON assessment.id = aa.assessment_id
    CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(
        CASE
            WHEN pg_catalog.jsonb_typeof(diagnosis.evidence->'matches') = 'array'
                THEN diagnosis.evidence->'matches'
            ELSE '[]'::jsonb
        END
    ) AS match_item(value)
    JOIN public.questions AS question
      ON question.id = (match_item.value->>'question_id')::uuid
     AND question.topic_id = diagnosis.topic_id
    WHERE aa.status = 'graded'
      AND diagnosis.created_at <= p_through
      AND diagnosis.evidence->>'rule_based' = 'true'
      AND (
          (p_class_id IS NULL AND p_student_id IS NOT NULL AND aa.student_id = p_student_id)
          OR (
              p_class_id IS NOT NULL
              AND assessment.class_id = p_class_id
              AND (p_student_id IS NULL OR aa.student_id = p_student_id)
              AND EXISTS (
                  SELECT 1 FROM public.enrollments AS e
                  WHERE e.class_id = p_class_id
                    AND e.student_id = aa.student_id
                    AND e.status = 'active'
              )
          )
      )
    GROUP BY aa.student_id, diagnosis.topic_id, COALESCE(question.concept, 'unclassified');
$$;

CREATE OR REPLACE FUNCTION private.calculate_student_progress(
    p_student_id uuid,
    p_as_of timestamptz
)
RETURNS TABLE (
    student_id uuid,
    topic_id uuid,
    topic_title text,
    topic_code text,
    subject text,
    grade_level smallint,
    learning_objective text,
    is_topic_level boolean,
    evidence_units integer,
    assessment_items integer,
    assessment_attempts integer,
    completed_practice_activities integer,
    evidence_days integer,
    latest_evidence_at timestamptz,
    weighted_accuracy numeric,
    mastery_status text,
    supported_diagnosis_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH evidence AS MATERIALIZED (
        SELECT * FROM private.learning_progress_evidence(p_student_id, NULL::uuid, p_as_of)
    ),
    weighted AS (
        SELECT evidence.*,
               private.learning_recency_weight(evidence.observed_at, p_as_of) AS recency_weight
        FROM evidence
        WHERE evidence.observed_at >= p_as_of - INTERVAL '90 days'
    ),
    aggregated AS (
        SELECT weighted.student_id,
               weighted.topic_id,
               weighted.topic_title,
               weighted.topic_code,
               weighted.subject,
               weighted.grade_level,
               (GROUPING(weighted.learning_objective) = 1) AS is_topic_level,
               CASE
                   WHEN GROUPING(weighted.learning_objective) = 1 THEN 'topic_overall'
                   ELSE weighted.learning_objective
               END AS learning_objective,
               pg_catalog.count(*)::integer AS evidence_units,
               pg_catalog.count(*) FILTER (WHERE weighted.evidence_type = 'assessment_item')::integer AS assessment_items,
               pg_catalog.count(DISTINCT weighted.attempt_id)
                   FILTER (WHERE weighted.evidence_type = 'assessment_item')::integer AS assessment_attempts,
               pg_catalog.count(*) FILTER (WHERE weighted.evidence_type = 'practice_activity')::integer AS completed_practice_activities,
               pg_catalog.count(DISTINCT (weighted.observed_at AT TIME ZONE 'UTC')::date)::integer AS evidence_days,
               pg_catalog.max(weighted.observed_at) AS latest_evidence_at,
               pg_catalog.sum(weighted.score * weighted.recency_weight)
                   / NULLIF(pg_catalog.sum(weighted.recency_weight), 0) AS weighted_accuracy
        FROM weighted
        GROUP BY GROUPING SETS (
            (weighted.student_id, weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level),
            (weighted.student_id, weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level, weighted.learning_objective)
        )
    )
    SELECT aggregated.student_id,
           aggregated.topic_id,
           aggregated.topic_title,
           aggregated.topic_code,
           aggregated.subject,
           aggregated.grade_level,
           aggregated.learning_objective,
           aggregated.is_topic_level,
           aggregated.evidence_units,
           aggregated.assessment_items,
           aggregated.assessment_attempts,
           aggregated.completed_practice_activities,
           aggregated.evidence_days,
           aggregated.latest_evidence_at,
           aggregated.weighted_accuracy,
           private.learning_mastery_status(
               aggregated.evidence_units,
               aggregated.evidence_days,
               aggregated.latest_evidence_at,
               p_as_of,
               aggregated.weighted_accuracy
           ) AS mastery_status,
           COALESCE((
               SELECT pg_catalog.sum(signal.diagnosis_count)::integer
               FROM private.learning_progress_diagnoses(p_student_id, NULL::uuid, p_as_of) AS signal
               WHERE signal.topic_id = aggregated.topic_id
                 AND (aggregated.is_topic_level OR signal.learning_objective = aggregated.learning_objective)
           ), 0)::integer AS supported_diagnosis_count
    FROM aggregated;
$$;

CREATE OR REPLACE FUNCTION private.persist_student_progress_snapshots(
    p_student_id uuid,
    p_as_of timestamptz,
    p_source_event_type text,
    p_source_event_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    INSERT INTO public.progress_records (
        class_id, student_id, topic_id, mastery_score, evidence_count, basis,
        recorded_at, learning_objective, is_topic_summary, calculation_version,
        mastery_status, evidence_through, evidence_summary, source_event_type, source_event_id
    )
    SELECT NULL::uuid,
           progress.student_id,
           progress.topic_id,
           CASE WHEN progress.mastery_status = 'insufficient_evidence' THEN NULL::numeric
                ELSE progress.weighted_accuracy END,
           progress.evidence_units,
           CASE
               WHEN progress.assessment_items > 0 AND progress.completed_practice_activities > 0 THEN 'combined'
               WHEN progress.completed_practice_activities > 0 THEN 'practice'
               ELSE 'assessment'
           END,
           pg_catalog.now(),
           progress.learning_objective,
           progress.is_topic_level,
           'mastery-v1',
           progress.mastery_status,
           progress.latest_evidence_at,
           pg_catalog.jsonb_build_object(
               'evidence_units', progress.evidence_units,
               'assessment_items', progress.assessment_items,
               'assessment_attempts', progress.assessment_attempts,
               'completed_practice_activities', progress.completed_practice_activities,
               'evidence_days', progress.evidence_days,
               'latest_evidence_at', progress.latest_evidence_at,
               'supported_diagnosis_count', progress.supported_diagnosis_count,
               'weighted_accuracy_percent',
                   CASE WHEN progress.mastery_status = 'insufficient_evidence' THEN NULL
                        ELSE pg_catalog.round(progress.weighted_accuracy * 100, 2) END
           ),
           p_source_event_type,
           p_source_event_id
    FROM private.calculate_student_progress(p_student_id, p_as_of) AS progress
    WHERE progress.evidence_units > 0
    ON CONFLICT (
        source_event_type, source_event_id, student_id, topic_id,
        learning_objective, is_topic_summary, calculation_version
    ) WHERE source_event_type IS NOT NULL AND source_event_id IS NOT NULL
    DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION private.record_assessment_progress_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.status = 'graded' AND OLD.status IS DISTINCT FROM 'graded' THEN
        PERFORM private.persist_student_progress_snapshots(
            NEW.student_id,
            COALESCE(NEW.submitted_at, pg_catalog.now()),
            'assessment_attempt',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER assessment_attempt_zz_stage5_progress_snapshot
AFTER UPDATE OF status ON public.assessment_attempts
FOR EACH ROW EXECUTE FUNCTION private.record_assessment_progress_snapshot();

CREATE OR REPLACE FUNCTION private.record_practice_progress_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_item_count integer;
    v_answered_count integer;
    v_student_id uuid;
    v_activity_type text;
BEGIN
    SELECT activity.student_id,
           activity.activity_type,
           pg_catalog.jsonb_array_length(
               CASE WHEN pg_catalog.jsonb_typeof(activity.content->'items') = 'array'
                    THEN activity.content->'items' ELSE '[]'::jsonb END
           )
    INTO v_student_id, v_activity_type, v_item_count
    FROM private.ai_learning_activities AS activity
    WHERE activity.id = NEW.activity_id;

    IF NOT FOUND OR v_activity_type <> 'practice' OR v_item_count < 1 THEN
        RETURN NEW;
    END IF;

    SELECT pg_catalog.count(DISTINCT response.item_id)::integer
    INTO v_answered_count
    FROM private.ai_practice_responses AS response
    WHERE response.activity_id = NEW.activity_id
      AND response.created_at <= NEW.created_at
      AND EXISTS (
          SELECT 1
          FROM private.ai_learning_activities AS activity
          CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(
              CASE WHEN pg_catalog.jsonb_typeof(activity.content->'items') = 'array'
                   THEN activity.content->'items' ELSE '[]'::jsonb END
          ) AS item(value)
          WHERE activity.id = NEW.activity_id
            AND item.value->>'id' = response.item_id::text
      );

    IF v_answered_count = v_item_count THEN
        PERFORM private.persist_student_progress_snapshots(
            v_student_id,
            NEW.created_at,
            'practice_response',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER ai_practice_response_zz_stage5_progress_snapshot
AFTER INSERT ON private.ai_practice_responses
FOR EACH ROW EXECUTE FUNCTION private.record_practice_progress_snapshot();

-- Backfill versioned observations from already-persisted source events. Source
-- attempts/responses remain the canonical history; these snapshots are derived,
-- append-only interpretations tagged with mastery-v1.
DO $$
DECLARE
    source_event record;
BEGIN
    FOR source_event IN
        SELECT aa.id, aa.student_id, aa.submitted_at
        FROM public.assessment_attempts AS aa
        WHERE aa.status = 'graded'
        ORDER BY aa.submitted_at, aa.id
    LOOP
        PERFORM private.persist_student_progress_snapshots(
            source_event.student_id,
            source_event.submitted_at,
            'assessment_attempt',
            source_event.id
        );
    END LOOP;

    FOR source_event IN
        WITH activity_items AS (
            SELECT activity.id AS activity_id,
                   activity.student_id,
                   item.value->>'id' AS item_key
            FROM private.ai_learning_activities AS activity
            CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(
                CASE WHEN pg_catalog.jsonb_typeof(activity.content->'items') = 'array'
                     THEN activity.content->'items' ELSE '[]'::jsonb END
            ) AS item(value)
            WHERE activity.activity_type = 'practice'
        ),
        latest_answers AS (
            SELECT DISTINCT ON (response.activity_id, response.item_id)
                   response.id AS response_id,
                   response.activity_id,
                   response.item_id,
                   response.created_at
            FROM private.ai_practice_responses AS response
            ORDER BY response.activity_id, response.item_id, response.created_at DESC, response.id DESC
        ),
        completed AS (
            SELECT activity_items.activity_id,
                   activity_items.student_id,
                   pg_catalog.max(latest_answers.created_at) AS completed_at,
                   (pg_catalog.array_agg(latest_answers.response_id
                       ORDER BY latest_answers.created_at DESC, latest_answers.response_id DESC))[1] AS event_id,
                   pg_catalog.count(activity_items.item_key) AS item_count,
                   pg_catalog.count(latest_answers.response_id) AS answered_count
            FROM activity_items
            LEFT JOIN latest_answers
              ON latest_answers.activity_id = activity_items.activity_id
             AND latest_answers.item_id::text = activity_items.item_key
            GROUP BY activity_items.activity_id, activity_items.student_id
            HAVING pg_catalog.count(activity_items.item_key) = pg_catalog.count(latest_answers.response_id)
        )
        SELECT completed.student_id, completed.completed_at, completed.event_id
        FROM completed
        JOIN private.ai_learning_activities AS activity ON activity.id = completed.activity_id
        WHERE completed.item_count > 0
        ORDER BY completed.completed_at, completed.event_id
    LOOP
        PERFORM private.persist_student_progress_snapshots(
            source_event.student_id,
            source_event.completed_at,
            'practice_response',
            source_event.event_id
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_progress_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
    v_as_of timestamptz := pg_catalog.now();
    v_topics jsonb;
    v_topic_count integer;
    v_topics_with_evidence integer;
    v_secure_topics integer;
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;

    WITH progress AS MATERIALIZED (
        SELECT * FROM private.calculate_student_progress(v_student_id, v_as_of)
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(
               pg_catalog.jsonb_build_object(
                   'topic_id', topic.id,
                   'topic_code', topic.code,
                   'topic_title', topic.title,
                   'subject', topic.subject,
                   'grade_level', topic.grade_level,
                   'status', COALESCE(summary.mastery_status, 'insufficient_evidence'),
                   'mastery_percent', CASE
                       WHEN summary.mastery_status = 'insufficient_evidence' OR summary.mastery_status IS NULL THEN NULL
                       ELSE pg_catalog.round(summary.weighted_accuracy * 100, 1)
                   END,
                   'evidence_units', COALESCE(summary.evidence_units, 0),
                   'assessment_items', COALESCE(summary.assessment_items, 0),
                   'assessment_attempts', COALESCE(summary.assessment_attempts, 0),
                   'completed_practice_activities', COALESCE(summary.completed_practice_activities, 0),
                   'evidence_days', COALESCE(summary.evidence_days, 0),
                   'latest_evidence_at', summary.latest_evidence_at,
                   'supported_diagnosis_count', COALESCE(summary.supported_diagnosis_count, 0),
                   'objectives', COALESCE(objectives.items, '[]'::jsonb)
               ) ORDER BY topic.subject, topic.grade_level, topic.title
           ), '[]'::jsonb),
           pg_catalog.count(*)::integer,
           pg_catalog.count(*) FILTER (WHERE summary.evidence_units > 0)::integer,
           pg_catalog.count(*) FILTER (WHERE summary.mastery_status = 'secure')::integer
    INTO v_topics, v_topic_count, v_topics_with_evidence, v_secure_topics
    FROM public.topics AS topic
    LEFT JOIN progress AS summary
      ON summary.topic_id = topic.id AND summary.is_topic_level
    LEFT JOIN LATERAL (
        SELECT pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'learning_objective', objective.learning_objective,
                       'status', objective.mastery_status,
                       'mastery_percent', CASE
                           WHEN objective.mastery_status = 'insufficient_evidence' THEN NULL
                           ELSE pg_catalog.round(objective.weighted_accuracy * 100, 1)
                       END,
                       'evidence_units', objective.evidence_units,
                       'assessment_items', objective.assessment_items,
                       'assessment_attempts', objective.assessment_attempts,
                       'completed_practice_activities', objective.completed_practice_activities,
                       'evidence_days', objective.evidence_days,
                       'latest_evidence_at', objective.latest_evidence_at,
                       'supported_diagnosis_count', objective.supported_diagnosis_count
                   ) ORDER BY objective.learning_objective
               ) AS items
        FROM progress AS objective
        WHERE objective.topic_id = topic.id AND NOT objective.is_topic_level
    ) AS objectives ON true
    WHERE topic.is_published;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'calculation_version', 'mastery-v1',
        'as_of', v_as_of,
        'totals', pg_catalog.jsonb_build_object(
            'published_topics', v_topic_count,
            'topics_with_evidence', v_topics_with_evidence,
            'secure_topics', v_secure_topics
        ),
        'topics', v_topics
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_topic_mastery(p_topic_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
    v_as_of timestamptz := pg_catalog.now();
    v_topic jsonb;
    v_mastery jsonb;
    v_objectives jsonb;
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    SELECT pg_catalog.jsonb_build_object(
               'topic_id', topic.id, 'topic_code', topic.code,
               'topic_title', topic.title, 'subject', topic.subject,
               'grade_level', topic.grade_level
           )
    INTO v_topic
    FROM public.topics AS topic
    WHERE topic.id = p_topic_id AND topic.is_published;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Published topic not found' USING ERRCODE = '22023';
    END IF;

    WITH progress AS MATERIALIZED (
        SELECT * FROM private.calculate_student_progress(v_student_id, v_as_of)
        WHERE topic_id = p_topic_id
    )
    SELECT COALESCE((
               SELECT pg_catalog.jsonb_build_object(
                   'status', mastery.mastery_status,
                   'mastery_percent', CASE WHEN mastery.mastery_status = 'insufficient_evidence' THEN NULL
                                           ELSE pg_catalog.round(mastery.weighted_accuracy * 100, 1) END,
                   'evidence_units', mastery.evidence_units,
                   'assessment_items', mastery.assessment_items,
                   'assessment_attempts', mastery.assessment_attempts,
                   'completed_practice_activities', mastery.completed_practice_activities,
                   'evidence_days', mastery.evidence_days,
                   'latest_evidence_at', mastery.latest_evidence_at,
                   'supported_diagnosis_count', mastery.supported_diagnosis_count
               ) FROM progress AS mastery WHERE mastery.is_topic_level
           ), pg_catalog.jsonb_build_object(
               'status', 'insufficient_evidence', 'mastery_percent', NULL,
               'evidence_units', 0, 'assessment_items', 0, 'assessment_attempts', 0,
               'completed_practice_activities', 0, 'evidence_days', 0,
               'latest_evidence_at', NULL, 'supported_diagnosis_count', 0
           )),
           COALESCE((
               SELECT pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'learning_objective', objective.learning_objective,
                       'status', objective.mastery_status,
                       'mastery_percent', CASE WHEN objective.mastery_status = 'insufficient_evidence' THEN NULL
                                               ELSE pg_catalog.round(objective.weighted_accuracy * 100, 1) END,
                       'evidence_units', objective.evidence_units,
                       'assessment_items', objective.assessment_items,
                       'assessment_attempts', objective.assessment_attempts,
                       'completed_practice_activities', objective.completed_practice_activities,
                       'evidence_days', objective.evidence_days,
                       'latest_evidence_at', objective.latest_evidence_at,
                       'supported_diagnosis_count', objective.supported_diagnosis_count
                   ) ORDER BY objective.learning_objective
               ) FROM progress AS objective WHERE NOT objective.is_topic_level
           ), '[]'::jsonb)
    INTO v_mastery, v_objectives;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'calculation_version', 'mastery-v1',
        'as_of', v_as_of,
        'topic', v_topic,
        'mastery', v_mastery,
        'objectives', v_objectives
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_assessment_history(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 100' USING ERRCODE = '22023';
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'attempts', COALESCE((
            SELECT pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'attempt_id', attempt.id,
                    'assessment_id', attempt.assessment_id,
                    'assessment_title', assessment.title,
                    'assessment_type', assessment.assessment_type,
                    'attempt_number', attempt.attempt_number,
                    'status', attempt.status,
                    'started_at', attempt.started_at,
                    'submitted_at', attempt.submitted_at,
                    'score_percent', attempt.score_percent,
                    'response_count', COALESCE(stats.response_count, 0),
                    'answered_count', COALESCE(stats.answered_count, 0),
                    'correct_count', COALESCE(stats.correct_count, 0),
                    'incorrect_count', COALESCE(stats.incorrect_count, 0),
                    'unanswered_count', COALESCE(stats.unanswered_count, 0),
                    'diagnosis_count', COALESCE(diagnoses.diagnosis_count, 0),
                    'topics', COALESCE(topics.items, '[]'::jsonb)
                ) ORDER BY attempt.started_at DESC, attempt.attempt_number DESC
            )
            FROM (
                SELECT aa.* FROM public.assessment_attempts AS aa
                WHERE aa.student_id = v_student_id
                ORDER BY aa.started_at DESC, aa.id
                LIMIT p_limit
            ) AS attempt
            JOIN public.assessments AS assessment ON assessment.id = attempt.assessment_id
            LEFT JOIN LATERAL (
                SELECT pg_catalog.count(*)::integer AS response_count,
                       pg_catalog.count(*) FILTER (WHERE response.is_answered)::integer AS answered_count,
                       pg_catalog.count(*) FILTER (WHERE response.is_correct IS TRUE)::integer AS correct_count,
                       pg_catalog.count(*) FILTER (WHERE response.is_correct IS FALSE AND response.is_answered)::integer AS incorrect_count,
                       pg_catalog.count(*) FILTER (WHERE NOT response.is_answered)::integer AS unanswered_count
                FROM public.responses AS response
                WHERE response.attempt_id = attempt.id
            ) AS stats ON true
            LEFT JOIN LATERAL (
                SELECT pg_catalog.count(*)::integer AS diagnosis_count
                FROM public.diagnoses AS diagnosis
                WHERE diagnosis.source_attempt_id = attempt.id
            ) AS diagnoses ON true
            LEFT JOIN LATERAL (
                SELECT pg_catalog.jsonb_agg(
                           pg_catalog.jsonb_build_object('topic_id', topic.id, 'topic_title', topic.title, 'topic_code', topic.code)
                           ORDER BY topic.title
                       ) AS items
                FROM (
                    SELECT DISTINCT question.topic_id
                    FROM public.responses AS response
                    JOIN public.questions AS question ON question.id = response.question_id
                    WHERE response.attempt_id = attempt.id
                ) AS used
                JOIN public.topics AS topic ON topic.id = used.topic_id
            ) AS topics ON true
        ), '[]'::jsonb),
        'total_attempts', (
            SELECT pg_catalog.count(*)::integer
            FROM public.assessment_attempts AS aa
            WHERE aa.student_id = v_student_id
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_recent_learning_activity(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
    v_as_of timestamptz := pg_catalog.now();
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 100' USING ERRCODE = '22023';
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'activity', COALESCE((
            SELECT pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'id', recent.id,
                    'activity_type', recent.activity_type,
                    'title', recent.title,
                    'topic_id', recent.topic_id,
                    'topic_title', recent.topic_title,
                    'learning_objective', recent.learning_objective,
                    'started_at', recent.started_at,
                    'completed_at', recent.completed_at,
                    'status', recent.activity_status,
                    'score_percent', recent.score_percent,
                    'attempt_number', recent.attempt_number,
                    'completed_items', recent.completed_items,
                    'total_items', recent.total_items
                ) ORDER BY recent.occurred_at DESC, recent.id
            )
            FROM (
                SELECT combined.*
                FROM (
                SELECT attempt.id,
                       'assessment'::text AS activity_type,
                       assessment.title,
                       NULL::uuid AS topic_id,
                       NULL::text AS topic_title,
                       NULL::text AS learning_objective,
                       attempt.started_at,
                       CASE WHEN attempt.status = 'graded' THEN attempt.submitted_at ELSE NULL END AS completed_at,
                       attempt.status AS activity_status,
                       attempt.score_percent,
                       attempt.attempt_number,
                       COALESCE(stats.answered_count, 0) AS completed_items,
                       COALESCE(stats.total_items, 0) AS total_items,
                       COALESCE(attempt.submitted_at, attempt.started_at) AS occurred_at
                FROM public.assessment_attempts AS attempt
                JOIN public.assessments AS assessment ON assessment.id = attempt.assessment_id
                LEFT JOIN LATERAL (
                    SELECT pg_catalog.count(*) FILTER (WHERE response.is_answered)::integer AS answered_count,
                           (SELECT pg_catalog.count(*)::integer FROM public.assessment_questions AS aq
                            WHERE aq.assessment_id = attempt.assessment_id) AS total_items
                    FROM public.responses AS response
                    WHERE response.attempt_id = attempt.id
                ) AS stats ON true
                WHERE attempt.student_id = v_student_id

                UNION ALL

                SELECT activity.id,
                       activity.activity_type,
                       CASE WHEN activity.activity_type = 'practice' THEN 'Targeted practice' ELSE 'Personalized explanation' END,
                       topic.id,
                       topic.title,
                       question.concept,
                       activity.created_at,
                       CASE
                           WHEN activity.activity_type = 'explanation' THEN activity.created_at
                           WHEN practice.completion_at IS NOT NULL THEN practice.completion_at
                           ELSE NULL
                       END,
                       CASE
                           WHEN activity.activity_type = 'explanation' OR practice.completion_at IS NOT NULL THEN 'completed'
                           ELSE 'in_progress'
                       END,
                       NULL::numeric,
                       NULL::integer,
                       COALESCE(practice.answered_items, 0),
                       COALESCE(practice.total_items, 0),
                       COALESCE(practice.last_response_at, activity.created_at)
                FROM private.ai_learning_activities AS activity
                JOIN public.questions AS question ON question.id = activity.question_id
                JOIN public.topics AS topic ON topic.id = question.topic_id
                LEFT JOIN LATERAL (
                    WITH items AS (
                        SELECT item.value->>'id' AS item_key
                        FROM pg_catalog.jsonb_array_elements(
                            CASE WHEN pg_catalog.jsonb_typeof(activity.content->'items') = 'array'
                                 THEN activity.content->'items' ELSE '[]'::jsonb END
                        ) AS item(value)
                    ),
                    first_answers AS (
                        SELECT DISTINCT ON (response.item_id)
                               response.item_id, response.created_at
                        FROM private.ai_practice_responses AS response
                        JOIN items ON items.item_key = response.item_id::text
                        WHERE response.activity_id = activity.id
                        ORDER BY response.item_id, response.created_at, response.id
                    )
                    SELECT (SELECT pg_catalog.count(*)::integer FROM items) AS total_items,
                           pg_catalog.count(first_answers.item_id)::integer AS answered_items,
                           CASE
                               WHEN pg_catalog.count(first_answers.item_id) = (SELECT pg_catalog.count(*) FROM items)
                                   THEN pg_catalog.max(first_answers.created_at)
                               ELSE NULL::timestamptz
                           END AS completion_at,
                           (SELECT pg_catalog.max(response.created_at)
                            FROM private.ai_practice_responses AS response
                            WHERE response.activity_id = activity.id) AS last_response_at
                    FROM first_answers
                ) AS practice ON activity.activity_type = 'practice'
                WHERE activity.student_id = v_student_id
                ) AS combined
                ORDER BY combined.occurred_at DESC, combined.id
                LIMIT p_limit
            ) AS recent
        ), '[]'::jsonb),
        'as_of', v_as_of
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_mastery_history(
    p_topic_id uuid,
    p_learning_objective text DEFAULT NULL,
    p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 200 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 200' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.topics WHERE id = p_topic_id AND is_published) THEN
        RAISE EXCEPTION 'Published topic not found' USING ERRCODE = '22023';
    END IF;
    IF p_learning_objective IS NOT NULL
       AND char_length(pg_catalog.btrim(p_learning_objective)) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Learning objective is invalid' USING ERRCODE = '22023';
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'calculation_version', 'mastery-v1',
        'topic_id', p_topic_id,
        'learning_objective', COALESCE(p_learning_objective, 'topic_overall'),
        'is_topic_summary', p_learning_objective IS NULL,
        'observations', COALESCE((
            SELECT pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'status', snapshot.mastery_status,
                    'mastery_percent', CASE WHEN snapshot.mastery_status = 'insufficient_evidence' THEN NULL
                                            ELSE pg_catalog.round(snapshot.mastery_score * 100, 1) END,
                    'evidence_units', snapshot.evidence_count,
                    'evidence_through', snapshot.evidence_through,
                    'recorded_at', snapshot.recorded_at,
                    'source_event_type', snapshot.source_event_type,
                    'calculation_version', snapshot.calculation_version,
                    'evidence_summary', snapshot.evidence_summary
                ) ORDER BY snapshot.evidence_through, snapshot.recorded_at,
                           snapshot.source_event_type, snapshot.source_event_id
            )
            FROM (
                SELECT progress.*
                FROM public.progress_records AS progress
                WHERE progress.student_id = v_student_id
                  AND progress.topic_id = p_topic_id
                  AND progress.calculation_version = 'mastery-v1'
                  AND progress.is_topic_summary = (p_learning_objective IS NULL)
                  AND (p_learning_objective IS NULL OR progress.learning_objective = p_learning_objective)
                ORDER BY progress.evidence_through DESC, progress.recorded_at DESC
                LIMIT p_limit
            ) AS snapshot
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_progress_comparison(
    p_period_days integer DEFAULT 30,
    p_topic_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_student_id uuid := (SELECT auth.uid());
    v_as_of timestamptz := pg_catalog.now();
    v_current_start timestamptz;
    v_previous_start timestamptz;
    v_items jsonb;
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_student() THEN
        RAISE EXCEPTION 'A student profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_period_days IS NULL OR p_period_days NOT BETWEEN 7 AND 180 THEN
        RAISE EXCEPTION 'Comparison period must be between 7 and 180 days' USING ERRCODE = '22023';
    END IF;
    IF p_topic_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.topics WHERE id = p_topic_id AND is_published
    ) THEN
        RAISE EXCEPTION 'Published topic not found' USING ERRCODE = '22023';
    END IF;

    v_current_start := v_as_of - (p_period_days * INTERVAL '1 day');
    v_previous_start := v_current_start - (p_period_days * INTERVAL '1 day');

    WITH previous_evidence AS (
        SELECT evidence.*,
               'previous'::text AS period_name,
               v_current_start AS period_end
        FROM private.learning_progress_evidence(v_student_id, NULL::uuid, v_current_start) AS evidence
        WHERE evidence.observed_at > v_previous_start
          AND evidence.observed_at <= v_current_start
          AND (p_topic_id IS NULL OR evidence.topic_id = p_topic_id)
    ),
    current_evidence AS (
        SELECT evidence.*,
               'current'::text AS period_name,
               v_as_of AS period_end
        FROM private.learning_progress_evidence(v_student_id, NULL::uuid, v_as_of) AS evidence
        WHERE evidence.observed_at > v_current_start
          AND evidence.observed_at <= v_as_of
          AND (p_topic_id IS NULL OR evidence.topic_id = p_topic_id)
    ),
    all_evidence AS (
        SELECT * FROM previous_evidence
        UNION ALL
        SELECT * FROM current_evidence
    ),
    weighted AS (
        SELECT all_evidence.*,
               private.learning_recency_weight(all_evidence.observed_at, all_evidence.period_end) AS recency_weight
        FROM all_evidence
        WHERE all_evidence.observed_at >= all_evidence.period_end - INTERVAL '90 days'
    ),
    periods AS (
        SELECT weighted.topic_id,
               weighted.topic_title,
               weighted.topic_code,
               weighted.subject,
               weighted.grade_level,
               weighted.period_name,
               (GROUPING(weighted.learning_objective) = 1) AS is_topic_level,
               CASE WHEN GROUPING(weighted.learning_objective) = 1 THEN 'topic_overall'
                    ELSE weighted.learning_objective END AS learning_objective,
               pg_catalog.count(*)::integer AS evidence_units,
               pg_catalog.count(DISTINCT weighted.attempt_id)
                   FILTER (WHERE weighted.evidence_type = 'assessment_item')::integer AS assessment_attempts,
               pg_catalog.count(*) FILTER (WHERE weighted.evidence_type = 'practice_activity')::integer AS completed_practice_activities,
               pg_catalog.count(DISTINCT (weighted.observed_at AT TIME ZONE 'UTC')::date)::integer AS evidence_days,
               pg_catalog.max(weighted.observed_at) AS latest_evidence_at,
               pg_catalog.max(weighted.period_end) AS period_end,
               pg_catalog.sum(weighted.score * weighted.recency_weight)
                   / NULLIF(pg_catalog.sum(weighted.recency_weight), 0) AS weighted_accuracy
        FROM weighted
        GROUP BY GROUPING SETS (
            (weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level, weighted.period_name),
            (weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level, weighted.period_name, weighted.learning_objective)
        )
    ),
    classified AS (
        SELECT periods.*,
               private.learning_mastery_status(
                   periods.evidence_units, periods.evidence_days,
                   periods.latest_evidence_at, periods.period_end, periods.weighted_accuracy
               ) AS period_status
        FROM periods
    ),
    previous_period AS (
        SELECT * FROM classified WHERE period_name = 'previous'
    ),
    current_period AS (
        SELECT * FROM classified WHERE period_name = 'current'
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(
               pg_catalog.jsonb_build_object(
                   'topic_id', COALESCE(current_period.topic_id, previous_period.topic_id),
                   'topic_title', COALESCE(current_period.topic_title, previous_period.topic_title),
                   'topic_code', COALESCE(current_period.topic_code, previous_period.topic_code),
                   'learning_objective', COALESCE(current_period.learning_objective, previous_period.learning_objective),
                   'is_topic_level', COALESCE(current_period.is_topic_level, previous_period.is_topic_level),
                   'comparable', COALESCE(previous_period.period_status <> 'insufficient_evidence'
                                      AND current_period.period_status <> 'insufficient_evidence', false),
                   'comparison_status', CASE
                       WHEN previous_period.period_status <> 'insufficient_evidence'
                        AND current_period.period_status <> 'insufficient_evidence' THEN 'comparable'
                       ELSE 'insufficient_evidence'
                   END,
                   'previous', pg_catalog.jsonb_build_object(
                       'status', COALESCE(previous_period.period_status, 'insufficient_evidence'),
                       'mastery_percent', CASE WHEN previous_period.period_status = 'insufficient_evidence' THEN NULL
                                               ELSE pg_catalog.round(previous_period.weighted_accuracy * 100, 1) END,
                       'evidence_units', COALESCE(previous_period.evidence_units, 0),
                       'assessment_attempts', COALESCE(previous_period.assessment_attempts, 0),
                       'completed_practice_activities', COALESCE(previous_period.completed_practice_activities, 0),
                       'evidence_days', COALESCE(previous_period.evidence_days, 0)
                   ),
                   'current', pg_catalog.jsonb_build_object(
                       'status', COALESCE(current_period.period_status, 'insufficient_evidence'),
                       'mastery_percent', CASE WHEN current_period.period_status = 'insufficient_evidence' THEN NULL
                                               ELSE pg_catalog.round(current_period.weighted_accuracy * 100, 1) END,
                       'evidence_units', COALESCE(current_period.evidence_units, 0),
                       'assessment_attempts', COALESCE(current_period.assessment_attempts, 0),
                       'completed_practice_activities', COALESCE(current_period.completed_practice_activities, 0),
                       'evidence_days', COALESCE(current_period.evidence_days, 0)
                   ),
                   'change_percentage_points', CASE
                       WHEN previous_period.period_status <> 'insufficient_evidence'
                        AND current_period.period_status <> 'insufficient_evidence'
                       THEN pg_catalog.round((current_period.weighted_accuracy - previous_period.weighted_accuracy) * 100, 1)
                       ELSE NULL
                   END
               ) ORDER BY COALESCE(current_period.topic_title, previous_period.topic_title),
                          COALESCE(current_period.is_topic_level, previous_period.is_topic_level) DESC,
                          COALESCE(current_period.learning_objective, previous_period.learning_objective)
           ), '[]'::jsonb)
    INTO v_items
    FROM previous_period
    FULL OUTER JOIN current_period
      ON current_period.topic_id = previous_period.topic_id
     AND current_period.is_topic_level = previous_period.is_topic_level
     AND current_period.learning_objective = previous_period.learning_objective;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'calculation_version', 'mastery-v1',
        'period_days', p_period_days,
        'previous_start', v_previous_start,
        'current_start', v_current_start,
        'as_of', v_as_of,
        'comparisons', v_items
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_class_learning_progress(
    p_class_id uuid,
    p_topic_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_as_of timestamptz := pg_catalog.now();
    v_topics jsonb;
    v_active_students integer;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_teacher() OR NOT private.owns_class(p_class_id) THEN
        RAISE EXCEPTION 'Only the owning teacher can view this class summary' USING ERRCODE = '42501';
    END IF;
    IF p_topic_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.topics WHERE id = p_topic_id AND is_published
    ) THEN
        RAISE EXCEPTION 'Published topic not found' USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.count(*)::integer INTO v_active_students
    FROM public.enrollments AS enrollment
    WHERE enrollment.class_id = p_class_id AND enrollment.status = 'active';

    WITH evidence AS MATERIALIZED (
        SELECT * FROM private.learning_progress_evidence(NULL::uuid, p_class_id, v_as_of)
        WHERE p_topic_id IS NULL OR topic_id = p_topic_id
    ),
    weighted AS (
        SELECT evidence.*,
               private.learning_recency_weight(evidence.observed_at, v_as_of) AS recency_weight
        FROM evidence
        WHERE evidence.observed_at >= v_as_of - INTERVAL '90 days'
    ),
    aggregated AS (
        SELECT weighted.topic_id,
               weighted.topic_title,
               weighted.topic_code,
               weighted.subject,
               weighted.grade_level,
               (GROUPING(weighted.learning_objective) = 1) AS is_topic_level,
               CASE WHEN GROUPING(weighted.learning_objective) = 1 THEN 'topic_overall'
                    ELSE weighted.learning_objective END AS learning_objective,
               pg_catalog.count(*)::integer AS evidence_units,
               pg_catalog.count(DISTINCT weighted.student_id)::integer AS students_with_evidence,
               pg_catalog.count(DISTINCT weighted.attempt_id)
                   FILTER (WHERE weighted.evidence_type = 'assessment_item')::integer AS assessment_attempts,
               pg_catalog.count(*) FILTER (WHERE weighted.evidence_type = 'practice_activity')::integer AS completed_practice_activities,
               pg_catalog.count(DISTINCT (weighted.observed_at AT TIME ZONE 'UTC')::date)::integer AS evidence_days,
               pg_catalog.max(weighted.observed_at) AS latest_evidence_at,
               pg_catalog.sum(weighted.score * weighted.recency_weight)
                   / NULLIF(pg_catalog.sum(weighted.recency_weight), 0) AS weighted_accuracy
        FROM weighted
        GROUP BY GROUPING SETS (
            (weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level),
            (weighted.topic_id, weighted.topic_title, weighted.topic_code, weighted.subject, weighted.grade_level, weighted.learning_objective)
        )
    ),
    classified AS (
        SELECT aggregated.*,
               private.learning_mastery_status(
                   aggregated.evidence_units,
                   aggregated.evidence_days,
                   aggregated.latest_evidence_at,
                   v_as_of,
                   aggregated.weighted_accuracy
               ) AS mastery_status
        FROM aggregated
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(
               pg_catalog.jsonb_build_object(
                   'topic_id', topic.id,
                   'topic_code', topic.code,
                   'topic_title', topic.title,
                   'subject', topic.subject,
                   'grade_level', topic.grade_level,
                   'status', COALESCE(aggregate.mastery_status, 'insufficient_evidence'),
                   'class_weighted_accuracy_percent', CASE
                       WHEN aggregate.mastery_status = 'insufficient_evidence' OR aggregate.mastery_status IS NULL THEN NULL
                       ELSE pg_catalog.round(aggregate.weighted_accuracy * 100, 1)
                   END,
                   'evidence_units', COALESCE(aggregate.evidence_units, 0),
                   'students_with_evidence', COALESCE(aggregate.students_with_evidence, 0),
                   'assessment_attempts', COALESCE(aggregate.assessment_attempts, 0),
                   'completed_practice_activities', COALESCE(aggregate.completed_practice_activities, 0),
                   'evidence_days', COALESCE(aggregate.evidence_days, 0),
                   'latest_evidence_at', aggregate.latest_evidence_at,
                   'supported_diagnosis_count', COALESCE(topic_diagnoses.diagnosis_count, 0),
                   'objectives', COALESCE(objectives.items, '[]'::jsonb)
               ) ORDER BY topic.subject, topic.grade_level, topic.title
           ), '[]'::jsonb)
    INTO v_topics
    FROM public.topics AS topic
    LEFT JOIN classified AS aggregate
      ON aggregate.topic_id = topic.id AND aggregate.is_topic_level
    LEFT JOIN LATERAL (
        SELECT pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'learning_objective', objective.learning_objective,
                       'status', objective.mastery_status,
                       'class_weighted_accuracy_percent', CASE
                           WHEN objective.mastery_status = 'insufficient_evidence' THEN NULL
                           ELSE pg_catalog.round(objective.weighted_accuracy * 100, 1)
                       END,
                       'evidence_units', objective.evidence_units,
                       'students_with_evidence', objective.students_with_evidence,
                       'assessment_attempts', objective.assessment_attempts,
                       'completed_practice_activities', objective.completed_practice_activities,
                       'evidence_days', objective.evidence_days,
                       'latest_evidence_at', objective.latest_evidence_at,
                       'supported_diagnosis_count', COALESCE(objective_diagnosis.diagnosis_count, 0)
                   ) ORDER BY objective.learning_objective
               ) AS items
        FROM classified AS objective
        LEFT JOIN LATERAL (
            SELECT pg_catalog.sum(signal.diagnosis_count)::integer AS diagnosis_count
            FROM private.learning_progress_diagnoses(NULL::uuid, p_class_id, v_as_of) AS signal
            WHERE signal.topic_id = objective.topic_id
              AND signal.learning_objective = objective.learning_objective
        ) AS objective_diagnosis ON true
        WHERE objective.topic_id = topic.id AND NOT objective.is_topic_level
    ) AS objectives ON true
    LEFT JOIN LATERAL (
        SELECT pg_catalog.sum(signal.diagnosis_count)::integer AS diagnosis_count
        FROM private.learning_progress_diagnoses(NULL::uuid, p_class_id, v_as_of) AS signal
        WHERE signal.topic_id = topic.id
    ) AS topic_diagnoses ON true
    WHERE topic.is_published
      AND (p_topic_id IS NULL OR topic.id = p_topic_id);

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1,
        'calculation_version', 'mastery-v1',
        'class_id', p_class_id,
        'as_of', v_as_of,
        'active_students', v_active_students,
        'scope', 'Aggregated records for active enrollments and assessments assigned to this class; no student identifiers are returned.',
        'topics', v_topics
    );
END;
$$;

REVOKE ALL ON FUNCTION private.learning_recency_weight(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.learning_mastery_status(integer, integer, timestamptz, timestamptz, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.learning_progress_evidence(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.learning_progress_diagnoses(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.calculate_student_progress(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.persist_student_progress_snapshots(uuid, timestamptz, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.record_assessment_progress_snapshot() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.record_practice_progress_snapshot() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_student_progress_overview() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_topic_mastery(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_assessment_history(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_recent_learning_activity(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_mastery_history(uuid, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_progress_comparison(integer, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_class_learning_progress(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_progress_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_topic_mastery(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_assessment_history(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_recent_learning_activity(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_mastery_history(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_progress_comparison(integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_learning_progress(uuid, uuid) TO authenticated;

COMMIT;
