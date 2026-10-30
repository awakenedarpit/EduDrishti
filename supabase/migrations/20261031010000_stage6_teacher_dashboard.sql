-- Stage 6: teacher classroom analytics and reporting RPCs.
-- Read-only analytics over persisted enrollments, attempts, scored responses, and
-- diagnosis evidence. Public entry points re-check teacher role and class ownership;
-- SECURITY DEFINER is used only with explicit class-scoped queries and a fixed path.
BEGIN;

CREATE INDEX IF NOT EXISTS assessment_attempts_class_analytics_idx
    ON public.assessment_attempts (assessment_id, student_id, attempt_number DESC, submitted_at DESC)
    WHERE status = 'graded';
CREATE INDEX IF NOT EXISTS responses_topic_analytics_idx
    ON public.responses (assessment_id, question_id, attempt_id)
    WHERE graded_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS diagnoses_attempt_topic_code_idx
    ON public.diagnoses (source_attempt_id, topic_id, misconception_code);

CREATE FUNCTION private.assert_teacher_class(p_class_id uuid, p_assessment_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
    END IF;
    IF NOT private.is_current_user_teacher() THEN
        RAISE EXCEPTION 'A teacher profile is required' USING ERRCODE = '42501';
    END IF;
    IF p_class_id IS NULL OR NOT private.owns_class(p_class_id) THEN
        RAISE EXCEPTION 'Class is not available to this teacher' USING ERRCODE = '42501';
    END IF;
    IF p_assessment_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.assessments AS a
        WHERE a.id = p_assessment_id AND a.class_id = p_class_id AND NOT a.is_template
    ) THEN
        RAISE EXCEPTION 'Assessment is not part of this class' USING ERRCODE = '42501';
    END IF;
END;
$$;

-- Shared assessment metrics. Participation counts distinct active-roster learners
-- who started any attempt (including abandoned attempts); scores use only the most
-- recent GRADED attempt per learner, never an unfinished retake.
CREATE FUNCTION private.teacher_assessment_metrics(p_class_id uuid, p_assessment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_enrolled bigint;
    v_started bigint;
    v_graded bigint;
    v_avg numeric;
    v_median numeric;
    v_graded_attempts bigint;
    v_total_attempts bigint;
    v_in_progress bigint;
    v_submitted bigint;
    v_abandoned bigint;
BEGIN
    SELECT pg_catalog.count(*) INTO v_enrolled
    FROM public.enrollments AS e
    WHERE e.class_id = p_class_id AND e.status = 'active';

    SELECT pg_catalog.count(DISTINCT aa.student_id),
           pg_catalog.count(*) FILTER (WHERE aa.status = 'in_progress'),
           pg_catalog.count(*) FILTER (WHERE aa.status = 'submitted'),
           pg_catalog.count(*) FILTER (WHERE aa.status = 'abandoned'),
           pg_catalog.count(*)
    INTO v_started, v_in_progress, v_submitted, v_abandoned, v_total_attempts
    FROM public.assessment_attempts AS aa
    JOIN public.enrollments AS e
      ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
    WHERE aa.assessment_id = p_assessment_id;

    WITH latest_graded AS (
        SELECT DISTINCT ON (aa.student_id) aa.student_id, aa.id, aa.score_percent
        FROM public.assessment_attempts AS aa
        JOIN public.enrollments AS e
          ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE aa.assessment_id = p_assessment_id AND aa.status = 'graded'
        ORDER BY aa.student_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    )
    SELECT pg_catalog.count(*), pg_catalog.round(pg_catalog.avg(lg.score_percent), 1),
           pg_catalog.round((pg_catalog.percentile_cont(0.5) WITHIN GROUP (ORDER BY lg.score_percent))::numeric, 1)
    INTO v_graded, v_avg, v_median
    FROM latest_graded AS lg;

    SELECT pg_catalog.count(*) INTO v_graded_attempts
    FROM public.assessment_attempts AS aa
    JOIN public.enrollments AS e
      ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
    WHERE aa.assessment_id = p_assessment_id AND aa.status = 'graded';

    RETURN pg_catalog.jsonb_build_object(
        'active_enrollment_count', v_enrolled,
        'participating_student_count', v_started,
        'participation_rate_percent', CASE WHEN v_enrolled = 0 THEN NULL
            ELSE pg_catalog.round(100.0 * v_started / v_enrolled, 1) END,
        'graded_student_count', v_graded,
        'graded_attempt_count', v_graded_attempts,
        'mean_latest_graded_score_percent', v_avg,
        'median_latest_graded_score_percent', v_median,
        'unfinished_attempt_count', v_in_progress + v_submitted + v_abandoned,
        'in_progress_attempt_count', v_in_progress,
        'submitted_ungraded_attempt_count', v_submitted,
        'abandoned_attempt_count', v_abandoned,
        'attempt_count_including_all_statuses', v_total_attempts,
        'score_denominator', 'active-roster learners with at least one graded attempt; one latest graded attempt per learner',
        'participation_denominator', 'active enrollments at query time; a learner counts once after any attempt is started'
    );
END;
$$;

-- Latest graded attempt per active learner and assessment. Each learner/topic score
-- is the points-weighted percent over scored items; unanswered items in graded work
-- are persisted as zero-point responses and remain in the denominator.
CREATE FUNCTION private.teacher_topic_mastery(p_class_id uuid, p_assessment_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH active_roster AS (
        SELECT pg_catalog.count(*)::bigint AS active_count
        FROM public.enrollments AS e
        WHERE e.class_id = p_class_id AND e.status = 'active'
    ),
    latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.*
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        JOIN public.enrollments AS e
          ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE a.class_id = p_class_id AND aa.status = 'graded'
          AND (p_assessment_id IS NULL OR aa.assessment_id = p_assessment_id)
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ),
    learner_topic AS (
        SELECT lg.student_id, q.topic_id,
               100.0 * pg_catalog.sum(r.points_earned) / NULLIF(pg_catalog.sum(aq.points), 0) AS score_percent,
               pg_catalog.count(DISTINCT lg.id)::bigint AS graded_assessment_count,
               pg_catalog.count(*)::bigint AS graded_item_count,
               pg_catalog.count(*) FILTER (WHERE NOT r.is_answered)::bigint AS unanswered_item_count
        FROM latest_graded AS lg
        JOIN public.assessment_questions AS aq ON aq.assessment_id = lg.assessment_id
        JOIN public.questions AS q ON q.id = aq.question_id
        JOIN public.responses AS r
          ON r.attempt_id = lg.id AND r.assessment_id = lg.assessment_id AND r.question_id = q.id
        WHERE r.graded_at IS NOT NULL AND r.points_earned IS NOT NULL
        GROUP BY lg.student_id, q.topic_id
    ),
    eligible_topics AS (
        SELECT DISTINCT q.topic_id
        FROM public.assessments AS a
        JOIN public.assessment_questions AS aq ON aq.assessment_id = a.id
        JOIN public.questions AS q ON q.id = aq.question_id
        WHERE a.class_id = p_class_id AND NOT a.is_template
          AND (p_assessment_id IS NULL OR a.id = p_assessment_id)
    ),
    grouped AS (
        SELECT t.id AS topic_id, t.code AS topic_code, t.title AS topic_title,
               ar.active_count,
               pg_catalog.count(lt.student_id)::bigint AS learners_with_evidence,
               COALESCE(pg_catalog.sum(lt.graded_assessment_count), 0)::bigint AS graded_assessment_observations,
               COALESCE(pg_catalog.sum(lt.graded_item_count), 0)::bigint AS graded_item_observations,
               COALESCE(pg_catalog.sum(lt.unanswered_item_count), 0)::bigint AS unanswered_item_observations,
               pg_catalog.round(pg_catalog.avg(lt.score_percent), 1) AS mean_mastery_percent,
               pg_catalog.count(*) FILTER (WHERE lt.score_percent < 40)::bigint AS below_40_count,
               pg_catalog.count(*) FILTER (WHERE lt.score_percent >= 40 AND lt.score_percent < 70)::bigint AS from_40_to_69_count,
               pg_catalog.count(*) FILTER (WHERE lt.score_percent >= 70)::bigint AS at_least_70_count
        FROM eligible_topics AS et
        JOIN public.topics AS t ON t.id = et.topic_id
        CROSS JOIN active_roster AS ar
        LEFT JOIN learner_topic AS lt ON lt.topic_id = t.id
        GROUP BY t.id, t.code, t.title, ar.active_count
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'topic_id', g.topic_id,
        'topic_code', g.topic_code,
        'topic_title', g.topic_title,
        'active_enrollment_count', g.active_count,
        'learners_with_evidence_count', g.learners_with_evidence,
        'learners_without_evidence_count', GREATEST(g.active_count - g.learners_with_evidence, 0),
        'mean_mastery_percent', g.mean_mastery_percent,
        'graded_assessment_observations', g.graded_assessment_observations,
        'graded_item_observations', g.graded_item_observations,
        'unanswered_item_observations', g.unanswered_item_observations,
        'mastery_bands', pg_catalog.jsonb_build_object(
            'below_40_further_practice', g.below_40_count,
            '40_to_below_70_developing', g.from_40_to_69_count,
            '70_or_above_secure_for_now', g.at_least_70_count,
            'denominator_learners_with_evidence', g.learners_with_evidence,
            'below_40_percent_of_evidence_learners', CASE WHEN g.learners_with_evidence = 0 THEN NULL ELSE pg_catalog.round(100.0 * g.below_40_count / g.learners_with_evidence, 1) END,
            '40_to_below_70_percent_of_evidence_learners', CASE WHEN g.learners_with_evidence = 0 THEN NULL ELSE pg_catalog.round(100.0 * g.from_40_to_69_count / g.learners_with_evidence, 1) END,
            '70_or_above_percent_of_evidence_learners', CASE WHEN g.learners_with_evidence = 0 THEN NULL ELSE pg_catalog.round(100.0 * g.at_least_70_count / g.learners_with_evidence, 1) END
        )
    ) ORDER BY g.topic_title, g.topic_id), '[]'::jsonb)
    FROM grouped AS g;
$$;

CREATE FUNCTION public.list_teacher_classes()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := (SELECT auth.uid());
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000'; END IF;
    IF NOT private.is_current_user_teacher() THEN RAISE EXCEPTION 'A teacher profile is required' USING ERRCODE = '42501'; END IF;
    RETURN COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'class_id', c.id, 'name', c.name, 'grade_level', c.grade_level,
            'subject', c.subject, 'description', c.description,
            'created_at', c.created_at,
            'active_enrollment_count', (SELECT pg_catalog.count(*) FROM public.enrollments AS e WHERE e.class_id = c.id AND e.status = 'active'),
            'assessment_count', (SELECT pg_catalog.count(*) FROM public.assessments AS a WHERE a.class_id = c.id AND NOT a.is_template)
        ) ORDER BY c.created_at DESC, c.id)
        FROM public.classes AS c
        WHERE c.teacher_id = v_user_id
    ), '[]'::jsonb);
END;
$$;

CREATE FUNCTION public.get_teacher_class_overview(p_class_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_class jsonb;
    v_performance jsonb;
    v_assessments jsonb;
    v_topics jsonb;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id);
    SELECT pg_catalog.jsonb_build_object('class_id', c.id, 'name', c.name,
           'grade_level', c.grade_level, 'subject', c.subject, 'description', c.description,
           'created_at', c.created_at,
           'active_enrollment_count', (SELECT pg_catalog.count(*) FROM public.enrollments AS e WHERE e.class_id = c.id AND e.status = 'active'))
    INTO v_class FROM public.classes AS c WHERE c.id = p_class_id;

    WITH latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.student_id, aa.assessment_id, aa.score_percent
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        JOIN public.enrollments AS e ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE a.class_id = p_class_id AND aa.status = 'graded'
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    )
    SELECT pg_catalog.jsonb_build_object(
        'learner_assessment_observations', pg_catalog.count(*),
        'learners_with_any_graded_assessment', pg_catalog.count(DISTINCT student_id),
        'mean_latest_graded_score_percent', pg_catalog.round(pg_catalog.avg(score_percent), 1),
        'score_denominator', 'latest graded attempt per active learner and class assessment; unfinished attempts excluded'
    ) INTO v_performance FROM latest_graded;

    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'assessment_id', a.id, 'title', a.title, 'assessment_type', a.assessment_type,
        'status', a.status, 'opens_at', a.opens_at, 'closes_at', a.closes_at,
        'analytics', private.teacher_assessment_metrics(p_class_id, a.id)
    ) ORDER BY a.created_at DESC, a.id), '[]'::jsonb)
    INTO v_assessments
    FROM public.assessments AS a
    WHERE a.class_id = p_class_id AND NOT a.is_template;

    v_topics := private.teacher_topic_mastery(p_class_id, NULL);
    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'class', v_class,
        'class_performance', v_performance,
        'assessment_summaries', v_assessments,
        'topic_mastery_distribution', v_topics
    );
END;
$$;

CREATE FUNCTION public.get_teacher_assessment_analytics(p_class_id uuid, p_assessment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM private.assert_teacher_class(p_class_id, p_assessment_id);
    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'class_id', p_class_id, 'assessment_id', p_assessment_id,
        'analytics', private.teacher_assessment_metrics(p_class_id, p_assessment_id),
        'topic_performance', private.teacher_topic_mastery(p_class_id, p_assessment_id)
    );
END;
$$;

CREATE FUNCTION public.get_teacher_misconception_heatmap(
    p_class_id uuid,
    p_assessment_id uuid DEFAULT NULL,
    p_topic_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_active bigint;
    v_cells jsonb;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id, p_assessment_id);
    IF p_topic_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.topics AS t WHERE t.id = p_topic_id) THEN
        RAISE EXCEPTION 'Topic was not found' USING ERRCODE = '22023';
    END IF;
    SELECT pg_catalog.count(*) INTO v_active FROM public.enrollments AS e
    WHERE e.class_id = p_class_id AND e.status = 'active';

    WITH latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.id, aa.student_id, aa.assessment_id
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id
        JOIN public.enrollments AS e ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE a.class_id = p_class_id AND aa.status = 'graded'
          AND (p_assessment_id IS NULL OR a.id = p_assessment_id)
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ),
    eligible AS (
        SELECT q.topic_id, pg_catalog.count(DISTINCT lg.id)::bigint AS eligible_attempts
        FROM latest_graded AS lg
        JOIN public.assessment_questions AS aq ON aq.assessment_id = lg.assessment_id
        JOIN public.questions AS q ON q.id = aq.question_id
        WHERE p_topic_id IS NULL OR q.topic_id = p_topic_id
        GROUP BY q.topic_id
    ),
    candidate_rows AS (
        -- Collapse duplicate codes/questions/reruns within one attempt to one
        -- attempt-topic-code signal; every signal remains explicitly uncertain.
        SELECT DISTINCT d.source_attempt_id, d.topic_id, d.misconception_code,
               lg.student_id, d.summary
        FROM latest_graded AS lg
        JOIN public.assessments AS a ON a.id = lg.assessment_id AND a.class_id = p_class_id
        JOIN public.diagnoses AS d ON d.source_attempt_id = lg.id
        WHERE (p_assessment_id IS NULL OR a.id = p_assessment_id)
          AND (p_topic_id IS NULL OR d.topic_id = p_topic_id)
    ),
    grouped AS (
        SELECT cr.topic_id, t.code AS topic_code, t.title AS topic_title,
               cr.misconception_code,
               pg_catalog.count(DISTINCT cr.source_attempt_id)::bigint AS attempts_with_candidate,
               pg_catalog.count(DISTINCT cr.student_id)::bigint AS students_with_candidate,
               pg_catalog.min(cr.summary) AS representative_candidate_summary,
               COALESCE(e.eligible_attempts, 0)::bigint AS eligible_graded_attempts
        FROM candidate_rows AS cr
        JOIN public.topics AS t ON t.id = cr.topic_id
        LEFT JOIN eligible AS e ON e.topic_id = cr.topic_id
        GROUP BY cr.topic_id, t.code, t.title, cr.misconception_code, e.eligible_attempts
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'topic_id', g.topic_id, 'topic_code', g.topic_code, 'topic_title', g.topic_title,
        'misconception_code', g.misconception_code,
        'interpretation', 'possible_pattern_not_confirmed',
        'representative_candidate_summary', g.representative_candidate_summary,
        'candidate_attempt_count', g.attempts_with_candidate,
        'students_with_candidate_count', g.students_with_candidate,
        'eligible_graded_attempt_count', g.eligible_graded_attempts,
        'candidate_attempt_rate_percent', CASE WHEN g.eligible_graded_attempts = 0 THEN NULL ELSE pg_catalog.round(100.0 * g.attempts_with_candidate / g.eligible_graded_attempts, 1) END,
        'active_enrollment_count', v_active,
        'candidate_student_rate_percent', CASE WHEN v_active = 0 THEN NULL ELSE pg_catalog.round(100.0 * g.students_with_candidate / v_active, 1) END,
        'denominator_note', 'Rates use latest graded attempt per active learner and assessment; candidate records are uncertain evidence, not confirmed diagnoses.'
    ) ORDER BY g.topic_title, g.attempts_with_candidate DESC, g.misconception_code), '[]'::jsonb)
    INTO v_cells FROM grouped AS g;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'class_id', p_class_id, 'assessment_id', p_assessment_id,
        'topic_id', p_topic_id, 'active_enrollment_count', v_active,
        'cells', v_cells,
        'candidate_interpretation', 'possible_pattern_not_confirmed',
        'empty_scope_note', 'An empty cells array means no supported diagnosis records were available in this scope; it is not evidence that no learner has difficulty.'
    );
END;
$$;

CREATE FUNCTION public.get_teacher_students_needing_support(p_class_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_for_review jsonb;
    v_insufficient jsonb;
    v_active bigint;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id);
    SELECT pg_catalog.count(*) INTO v_active FROM public.enrollments AS e
    WHERE e.class_id = p_class_id AND e.status = 'active';

    WITH active_roster AS (
        SELECT e.student_id, p.display_name
        FROM public.enrollments AS e
        JOIN public.profiles AS p ON p.user_id = e.student_id AND p.app_role = 'student'
        WHERE e.class_id = p_class_id AND e.status = 'active'
    ),
    latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.*
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        JOIN active_roster AS r ON r.student_id = aa.student_id
        WHERE aa.status = 'graded'
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ),
    recent_ranked AS (
        SELECT lg.*, pg_catalog.row_number() OVER (PARTITION BY lg.student_id ORDER BY lg.submitted_at DESC, lg.id DESC) AS recent_rank
        FROM latest_graded AS lg
    ),
    score_summary AS (
        SELECT student_id, pg_catalog.count(*)::bigint AS graded_assessment_count,
               pg_catalog.round(pg_catalog.avg(score_percent) FILTER (WHERE recent_rank <= 3), 1) AS recent_mean_score_percent
        FROM recent_ranked GROUP BY student_id
    ),
    repeated_errors AS (
        SELECT lg.student_id, q.topic_id, pg_catalog.count(DISTINCT lg.id)::bigint AS incorrect_attempts
        FROM latest_graded AS lg
        JOIN public.assessment_questions AS aq ON aq.assessment_id = lg.assessment_id
        JOIN public.questions AS q ON q.id = aq.question_id
        JOIN public.responses AS r ON r.attempt_id = lg.id AND r.question_id = q.id
        WHERE r.is_answered AND r.is_correct IS FALSE
        GROUP BY lg.student_id, q.topic_id
        HAVING pg_catalog.count(DISTINCT lg.id) >= 2
    ),
    repeated_candidates AS (
        SELECT lg.student_id, d.misconception_code,
               pg_catalog.count(DISTINCT lg.id)::bigint AS candidate_attempts
        FROM latest_graded AS lg
        JOIN public.diagnoses AS d ON d.source_attempt_id = lg.id
        GROUP BY lg.student_id, d.misconception_code
        HAVING pg_catalog.count(DISTINCT lg.id) >= 2
    ),
    flags AS (
        SELECT r.student_id, r.display_name,
               COALESCE(s.graded_assessment_count, 0)::bigint AS graded_assessment_count,
               s.recent_mean_score_percent,
               (SELECT pg_catalog.count(*) FROM repeated_errors AS re WHERE re.student_id = r.student_id)::bigint AS repeated_error_topic_count,
               (SELECT pg_catalog.count(*) FROM repeated_candidates AS rc WHERE rc.student_id = r.student_id)::bigint AS repeated_candidate_code_count,
               COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                   'topic_id', re.topic_id, 'topic_title', t.title, 'incorrect_graded_attempt_count', re.incorrect_attempts,
                   'evidence_interpretation', 'observed_incorrect_responses_not_a_personal_trait'
               ) ORDER BY t.title, re.topic_id) FROM repeated_errors AS re JOIN public.topics AS t ON t.id = re.topic_id WHERE re.student_id = r.student_id), '[]'::jsonb) AS repeated_error_evidence,
               COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                   'misconception_code', rc.misconception_code, 'candidate_attempt_count', rc.candidate_attempts,
                   'interpretation', 'possible_pattern_not_confirmed'
               ) ORDER BY rc.misconception_code) FROM repeated_candidates AS rc WHERE rc.student_id = r.student_id), '[]'::jsonb) AS repeated_candidate_evidence
        FROM active_roster AS r
        LEFT JOIN score_summary AS s ON s.student_id = r.student_id
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'student_id', f.student_id, 'display_name', f.display_name,
        'evidence_status', 'review_recommended',
        'graded_assessment_count', f.graded_assessment_count,
        'recent_mean_score_percent', f.recent_mean_score_percent,
        'criteria_met', pg_catalog.to_jsonb(ARRAY_REMOVE(ARRAY[
            CASE WHEN f.graded_assessment_count >= 2 AND f.recent_mean_score_percent <= 60 THEN 'recent_mean_at_or_below_60_percent_across_at_least_two_assessments' END,
            CASE WHEN f.repeated_error_topic_count > 0 THEN 'same_topic_incorrect_responses_across_at_least_two_graded_assessments' END,
            CASE WHEN f.repeated_candidate_code_count > 0 THEN 'same_uncertain_candidate_code_across_at_least_two_graded_assessments' END
        ], NULL)),
        'repeated_error_evidence', f.repeated_error_evidence,
        'repeated_candidate_evidence', f.repeated_candidate_evidence,
        'supportive_note', 'This is a prompt to check in and offer a learning opportunity, not a label or conclusion about the learner.'
    ) ORDER BY f.recent_mean_score_percent NULLS LAST, f.student_id), '[]'::jsonb)
    INTO v_for_review
    FROM flags AS f
    WHERE (f.graded_assessment_count >= 2 AND f.recent_mean_score_percent <= 60)
       OR f.repeated_error_topic_count > 0 OR f.repeated_candidate_code_count > 0;

    WITH active_roster AS (
        SELECT e.student_id, p.display_name
        FROM public.enrollments AS e JOIN public.profiles AS p ON p.user_id = e.student_id AND p.app_role = 'student'
        WHERE e.class_id = p_class_id AND e.status = 'active'
    ),
    evidence AS (
        SELECT DISTINCT aa.student_id, aa.assessment_id
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        JOIN public.enrollments AS e ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE aa.status = 'graded'
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'student_id', r.student_id, 'display_name', r.display_name,
        'evidence_status', 'insufficient_evidence',
        'graded_assessment_count', COALESCE(s.assessment_count, 0),
        'evidence_note', 'Fewer than two distinct graded assessments are available. No performance concern is inferred; gather more evidence before drawing conclusions.'
    ) ORDER BY r.student_id), '[]'::jsonb)
    INTO v_insufficient
    FROM active_roster AS r
    LEFT JOIN (SELECT student_id, pg_catalog.count(*)::bigint AS assessment_count FROM evidence GROUP BY student_id) AS s
      ON s.student_id = r.student_id
    WHERE COALESCE(s.assessment_count, 0) < 2
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_for_review, '[]'::jsonb)) AS item WHERE item.value->>'student_id' = r.student_id::text);

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'class_id', p_class_id,
        'active_enrollment_count', v_active,
        'students_for_review', COALESCE(v_for_review, '[]'::jsonb),
        'insufficient_evidence', COALESCE(v_insufficient, '[]'::jsonb),
        'criteria', pg_catalog.jsonb_build_object(
            'recent_score', 'At least two latest-graded-per-assessment observations and mean of the three most recent observations at or below 60%; incomplete attempts are excluded.',
            'repeated_error', 'At least one topic with an answered incorrect response in two or more latest graded assessments.',
            'repeated_candidate', 'The same persisted candidate code in two or more latest graded assessments; always treated as uncertain.',
            'insufficient_evidence', 'Fewer than two distinct graded assessments and no other review criterion; presented as an evidence gap, not a concern.'
        )
    );
END;
$$;

CREATE FUNCTION public.get_teacher_student_learning_detail(p_class_id uuid, p_student_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_detail jsonb;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id);
    IF p_student_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.enrollments AS e WHERE e.class_id = p_class_id AND e.student_id = p_student_id
    ) THEN
        RAISE EXCEPTION 'Student is not part of this class' USING ERRCODE = '42501';
    END IF;

    WITH attempts AS (
        SELECT aa.*, a.title AS assessment_title, a.assessment_type,
               pg_catalog.row_number() OVER (ORDER BY COALESCE(aa.submitted_at, aa.started_at) DESC, aa.id DESC) AS history_rank
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        WHERE aa.student_id = p_student_id
    ),
    attempt_history AS (
        SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'attempt_id', x.id, 'assessment_id', x.assessment_id, 'assessment_title', x.assessment_title,
            'assessment_type', x.assessment_type, 'attempt_number', x.attempt_number,
            'status', x.status, 'started_at', x.started_at, 'submitted_at', x.submitted_at,
            'score_percent', x.score_percent,
            'candidate_signal_count', (SELECT pg_catalog.count(DISTINCT (d.topic_id, d.misconception_code))
                FROM public.diagnoses AS d WHERE d.source_attempt_id = x.id),
            'candidate_signal_interpretation', 'possible_pattern_not_confirmed'
        ) ORDER BY x.history_rank), '[]'::jsonb) AS items,
        (SELECT pg_catalog.count(*) FROM attempts) AS total_count
        FROM attempts AS x WHERE x.history_rank <= 50
    ),
    latest_graded AS (
        SELECT DISTINCT ON (aa.assessment_id) aa.*
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        WHERE aa.student_id = p_student_id AND aa.status = 'graded'
        ORDER BY aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ),
    topic_scores AS (
        SELECT q.topic_id,
               pg_catalog.round((100.0 * pg_catalog.sum(r.points_earned) / NULLIF(pg_catalog.sum(aq.points), 0))::numeric, 1) AS score_percent,
               pg_catalog.count(DISTINCT lg.id)::bigint AS graded_assessment_count
        FROM latest_graded AS lg
        JOIN public.assessment_questions AS aq ON aq.assessment_id = lg.assessment_id
        JOIN public.questions AS q ON q.id = aq.question_id
        JOIN public.responses AS r ON r.attempt_id = lg.id AND r.question_id = q.id AND r.graded_at IS NOT NULL
        GROUP BY q.topic_id
    ),
    topics AS (
        SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'topic_id', ts.topic_id, 'topic_title', t.title,
            'latest_graded_mastery_percent', ts.score_percent,
            'graded_assessment_count', ts.graded_assessment_count
        ) ORDER BY t.title, ts.topic_id), '[]'::jsonb) AS items
        FROM topic_scores AS ts JOIN public.topics AS t ON t.id = ts.topic_id
    ),
    candidate_signals AS (
        SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'topic_id', d.topic_id, 'topic_title', t.title,
            'misconception_code', d.misconception_code,
            'candidate_attempt_count', pg_catalog.count(DISTINCT d.source_attempt_id),
            'interpretation', 'possible_pattern_not_confirmed',
            'representative_summary', pg_catalog.min(d.summary)
        ) ORDER BY t.title, d.misconception_code), '[]'::jsonb) AS items
        FROM public.diagnoses AS d
        JOIN public.assessment_attempts AS aa ON aa.id = d.source_attempt_id AND aa.student_id = p_student_id
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        JOIN public.topics AS t ON t.id = d.topic_id
    )
    SELECT pg_catalog.jsonb_build_object(
        'student_id', p.user_id, 'display_name', p.display_name,
        'enrollment_status', e.status,
        'attempt_history', ah.items, 'attempt_history_total_count', ah.total_count,
        'attempt_history_truncated', ah.total_count > 50,
        'topic_learning_observations', tp.items,
        'candidate_signals', cs.items,
        'candidate_signal_note', 'Automated or legacy diagnosis records are uncertain candidate signals, not confirmed explanations of a learner’s reasoning.'
    ) INTO v_detail
    FROM public.profiles AS p
    JOIN public.enrollments AS e ON e.student_id = p.user_id AND e.class_id = p_class_id
    CROSS JOIN attempt_history AS ah CROSS JOIN topics AS tp CROSS JOIN candidate_signals AS cs
    WHERE p.user_id = p_student_id;
    RETURN v_detail;
END;
$$;

CREATE FUNCTION public.get_teacher_teaching_recommendations(p_class_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_recommendations jsonb := '[]'::jsonb;
    v_topic jsonb;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id);
    FOR v_topic IN SELECT value FROM jsonb_array_elements(private.teacher_topic_mastery(p_class_id, NULL)) AS topic(value)
    LOOP
        IF (v_topic->>'learners_with_evidence_count')::bigint >= 2
           AND (v_topic->>'mean_mastery_percent') IS NOT NULL
           AND (v_topic->>'mean_mastery_percent')::numeric < 70 THEN
            v_recommendations := v_recommendations || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                'topic_id', v_topic->'topic_id', 'topic_title', v_topic->'topic_title',
                'action', CASE WHEN (v_topic->>'mean_mastery_percent')::numeric < 40
                    THEN 'Revisit the concept and organize a short small-group revision session.'
                    ELSE 'Assign targeted practice and review the next set of responses.' END,
                'evidence', pg_catalog.jsonb_build_object(
                    'mean_mastery_percent', v_topic->'mean_mastery_percent',
                    'learners_with_evidence_count', v_topic->'learners_with_evidence_count',
                    'graded_item_observations', v_topic->'graded_item_observations',
                    'threshold_percent', 70,
                    'basis', 'points-weighted scores from each active learner’s latest graded attempt per assessment; unfinished attempts excluded'
                ),
                'confidence_note', 'A class-level teaching prompt, not a judgment about any individual learner.'
            ));
        END IF;
    END LOOP;

    WITH latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.id, aa.student_id, aa.assessment_id
        FROM public.assessment_attempts AS aa
        JOIN public.assessments AS a ON a.id = aa.assessment_id AND a.class_id = p_class_id
        JOIN public.enrollments AS e ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE aa.status = 'graded'
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ), repeated_codes AS (
        SELECT d.topic_id, t.title, d.misconception_code,
               pg_catalog.count(DISTINCT lg.student_id) AS distinct_students,
               pg_catalog.count(DISTINCT d.source_attempt_id) AS candidate_attempts
        FROM public.diagnoses AS d
        JOIN latest_graded AS lg ON lg.id = d.source_attempt_id
        JOIN public.topics AS t ON t.id = d.topic_id
        GROUP BY d.topic_id, t.title, d.misconception_code
        HAVING pg_catalog.count(DISTINCT d.source_attempt_id) >= 2
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'topic_id', rc.topic_id, 'topic_title', rc.title,
        'action', 'Offer a short targeted practice item and check which approach learners used; treat the recorded pattern as a question to explore, not a confirmed misconception.',
        'evidence', pg_catalog.jsonb_build_object(
            'misconception_code', rc.misconception_code,
            'candidate_attempt_count', rc.candidate_attempts,
            'distinct_students', rc.distinct_students,
            'interpretation', 'possible_pattern_not_confirmed'
        ),
        'confidence_note', 'This recommendation is linked to persisted candidate records; the records do not establish learner reasoning.'
    ) ORDER BY rc.title, rc.misconception_code), '[]'::jsonb)
    INTO v_topic FROM repeated_codes AS rc;
    v_recommendations := v_recommendations || COALESCE(v_topic, '[]'::jsonb);

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'class_id', p_class_id,
        'recommendations', v_recommendations,
        'empty_evidence_note', 'No evidence-linked teaching prompts met the stated thresholds. This does not establish that no further teaching is useful.'
    );
END;
$$;

CREATE FUNCTION public.get_teacher_assessment_report_data(p_class_id uuid, p_assessment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_class jsonb;
    v_assessment jsonb;
    v_metrics jsonb;
    v_topics jsonb;
    v_questions jsonb;
BEGIN
    PERFORM private.assert_teacher_class(p_class_id, p_assessment_id);
    SELECT pg_catalog.jsonb_build_object('class_id', c.id, 'name', c.name,
        'grade_level', c.grade_level, 'subject', c.subject)
    INTO v_class FROM public.classes AS c WHERE c.id = p_class_id;
    SELECT pg_catalog.jsonb_build_object('assessment_id', a.id, 'title', a.title,
        'assessment_type', a.assessment_type, 'status', a.status,
        'created_at', a.created_at, 'opens_at', a.opens_at, 'closes_at', a.closes_at)
    INTO v_assessment FROM public.assessments AS a WHERE a.id = p_assessment_id AND a.class_id = p_class_id;
    v_metrics := private.teacher_assessment_metrics(p_class_id, p_assessment_id);
    v_topics := private.teacher_topic_mastery(p_class_id, p_assessment_id);

    WITH latest_graded AS (
        SELECT DISTINCT ON (aa.student_id, aa.assessment_id) aa.*
        FROM public.assessment_attempts AS aa
        JOIN public.enrollments AS e ON e.class_id = p_class_id AND e.student_id = aa.student_id AND e.status = 'active'
        WHERE aa.assessment_id = p_assessment_id AND aa.status = 'graded'
        ORDER BY aa.student_id, aa.assessment_id, aa.attempt_number DESC, aa.submitted_at DESC, aa.id DESC
    ),
    by_question AS (
        SELECT q.id AS question_id, aq.position, q.topic_id, t.title AS topic_title,
               pg_catalog.count(r.id)::bigint AS graded_response_count,
               pg_catalog.count(*) FILTER (WHERE r.is_correct IS TRUE)::bigint AS correct_response_count,
               pg_catalog.count(*) FILTER (WHERE r.is_answered IS FALSE)::bigint AS unanswered_response_count,
               pg_catalog.round(pg_catalog.avg(r.score_percent), 1) AS mean_item_score_percent
        FROM public.assessment_questions AS aq
        JOIN public.questions AS q ON q.id = aq.question_id
        JOIN public.topics AS t ON t.id = q.topic_id
        LEFT JOIN latest_graded AS lg ON true
        LEFT JOIN public.responses AS r
          ON r.attempt_id = lg.id AND r.assessment_id = aq.assessment_id AND r.question_id = q.id
         AND r.graded_at IS NOT NULL
        WHERE aq.assessment_id = p_assessment_id
        GROUP BY q.id, aq.position, q.topic_id, t.title
    )
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'question_id', bq.question_id, 'position', bq.position,
        'topic_id', bq.topic_id, 'topic_title', bq.topic_title,
        'graded_response_count', bq.graded_response_count,
        'correct_response_count', bq.correct_response_count,
        'unanswered_response_count', bq.unanswered_response_count,
        'mean_item_score_percent', bq.mean_item_score_percent,
        'accuracy_denominator', 'latest graded attempt per active enrolled learner; unanswered graded responses count as zero; no answer text or answer key is returned'
    ) ORDER BY bq.position), '[]'::jsonb)
    INTO v_questions FROM by_question AS bq;

    RETURN pg_catalog.jsonb_build_object(
        'schema_version', 1, 'generated_at', pg_catalog.now(),
        'class', v_class, 'assessment', v_assessment,
        'analytics', v_metrics,
        'topic_performance', v_topics,
        'question_performance', v_questions,
        'export_safety', pg_catalog.jsonb_build_object(
            'contains_student_identifiers', false,
            'contains_submitted_answers', false,
            'contains_answer_keys', false,
            'access_rule', 'Only the authenticated owning teacher can generate this class-scoped aggregate report.'
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION private.assert_teacher_class(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.teacher_assessment_metrics(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.teacher_topic_mastery(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_teacher_classes() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_class_overview(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_assessment_analytics(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_misconception_heatmap(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_students_needing_support(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_student_learning_detail(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_teaching_recommendations(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_teacher_assessment_report_data(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_teacher_classes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_class_overview(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_assessment_analytics(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_misconception_heatmap(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_students_needing_support(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_student_learning_detail(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_teaching_recommendations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_assessment_report_data(uuid, uuid) TO authenticated;

COMMIT;
