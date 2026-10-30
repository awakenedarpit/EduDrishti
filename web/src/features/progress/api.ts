import type { Json } from "../../lib/database.types";
import { AppError, friendlyBackendError } from "../../lib/backend-errors";
import { requireSupabase } from "../../lib/supabase";

export type MasteryStatus = "insufficient_evidence" | "emerging" | "developing" | "secure";

export type ObjectiveProgress = {
  learning_objective: string;
  status: MasteryStatus;
  mastery_percent: number | null;
  evidence_units: number;
  assessment_items: number;
  assessment_attempts: number;
  completed_practice_activities: number;
  evidence_days: number;
  latest_evidence_at: string | null;
  supported_diagnosis_count: number;
};

export type TopicProgress = {
  topic_id: string;
  topic_code: string;
  topic_title: string;
  subject: string;
  grade_level: number;
  status: MasteryStatus;
  mastery_percent: number | null;
  evidence_units: number;
  assessment_items: number;
  assessment_attempts: number;
  completed_practice_activities: number;
  evidence_days: number;
  latest_evidence_at: string | null;
  supported_diagnosis_count: number;
  objectives: ObjectiveProgress[];
};

export type StudentProgressOverview = {
  schema_version: number;
  calculation_version: string;
  as_of: string;
  totals: {
    published_topics: number;
    topics_with_evidence: number;
    secure_topics: number;
  };
  topics: TopicProgress[];
};

export type ProgressWindow = {
  status: MasteryStatus;
  mastery_percent: number | null;
  evidence_units: number;
  assessment_attempts: number;
  completed_practice_activities: number;
  evidence_days: number;
};

export type ProgressComparisonItem = {
  topic_id: string;
  topic_title: string;
  topic_code: string;
  learning_objective: string;
  is_topic_level: boolean;
  comparable: boolean;
  comparison_status: "comparable" | "insufficient_evidence";
  previous: ProgressWindow;
  current: ProgressWindow;
  change_percentage_points: number | null;
};

export type StudentProgressComparison = {
  schema_version: number;
  calculation_version: string;
  period_days: number;
  previous_start: string;
  current_start: string;
  as_of: string;
  comparisons: ProgressComparisonItem[];
};

export type AssessmentHistoryAttempt = {
  attempt_id: string;
  assessment_id: string;
  assessment_title: string;
  assessment_type: "diagnostic" | "practice" | "summative";
  attempt_number: number;
  status: "in_progress" | "submitted" | "graded" | "abandoned";
  started_at: string;
  submitted_at: string | null;
  score_percent: number | null;
  response_count: number;
  answered_count: number;
  correct_count: number;
  incorrect_count: number;
  unanswered_count: number;
  diagnosis_count: number;
  topics: Array<{ topic_id: string; topic_title: string; topic_code: string }>;
};

export type StudentAssessmentHistory = {
  schema_version: number;
  attempts: AssessmentHistoryAttempt[];
  total_attempts: number;
};

export type RecentLearningActivity = {
  id: string;
  activity_type: "assessment" | "practice" | "explanation";
  title: string;
  topic_id: string | null;
  topic_title: string | null;
  learning_objective: string | null;
  started_at: string;
  completed_at: string | null;
  status: "in_progress" | "submitted" | "graded" | "abandoned" | "completed";
  score_percent: number | null;
  attempt_number: number | null;
  completed_items: number;
  total_items: number;
};

export type RecentLearningActivityList = {
  schema_version: number;
  activity: RecentLearningActivity[];
  as_of: string;
};

export type MasteryObservation = {
  status: MasteryStatus;
  mastery_percent: number | null;
  evidence_units: number;
  evidence_through: string;
  recorded_at: string;
  source_event_type: "assessment_attempt" | "practice_response";
  calculation_version: string;
  evidence_summary: Record<string, unknown>;
};

export type StudentMasteryHistory = {
  schema_version: number;
  calculation_version: string;
  topic_id: string;
  learning_objective: string;
  is_topic_summary: boolean;
  observations: MasteryObservation[];
};

export type ClassObjectiveProgress = Omit<ObjectiveProgress, "mastery_percent"> & {
  class_weighted_accuracy_percent: number | null;
  students_with_evidence: number;
};

export type ClassTopicProgress = {
  topic_id: string;
  topic_code: string;
  topic_title: string;
  subject: string;
  grade_level: number;
  status: MasteryStatus;
  class_weighted_accuracy_percent: number | null;
  evidence_units: number;
  students_with_evidence: number;
  assessment_attempts: number;
  completed_practice_activities: number;
  evidence_days: number;
  latest_evidence_at: string | null;
  supported_diagnosis_count: number;
  objectives: ClassObjectiveProgress[];
};

export type ClassLearningProgress = {
  schema_version: number;
  calculation_version: string;
  class_id: string;
  as_of: string;
  active_students: number;
  scope: string;
  topics: ClassTopicProgress[];
};

function parseObject<T>(data: Json | null, error: unknown, description: string): T {
  if (error) throw friendlyBackendError(error);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new AppError(`${description} returned an unexpected response.`);
  }
  return data as T;
}

export async function getStudentProgressOverview(): Promise<StudentProgressOverview> {
  const { data, error } = await requireSupabase().rpc("get_student_progress_overview");
  return parseObject<StudentProgressOverview>(data, error, "The progress overview");
}

export async function getStudentTopicMastery(topicId: string): Promise<{
  schema_version: number;
  calculation_version: string;
  as_of: string;
  topic: Pick<TopicProgress, "topic_id" | "topic_code" | "topic_title" | "subject" | "grade_level">;
  mastery: Omit<ObjectiveProgress, "learning_objective">;
  objectives: ObjectiveProgress[];
}> {
  const { data, error } = await requireSupabase().rpc("get_student_topic_mastery", { p_topic_id: topicId });
  return parseObject(data, error, "Topic mastery");
}

export async function getStudentAssessmentHistory(limit = 50): Promise<StudentAssessmentHistory> {
  const { data, error } = await requireSupabase().rpc("get_student_assessment_history", { p_limit: limit });
  return parseObject<StudentAssessmentHistory>(data, error, "Assessment history");
}

export async function getStudentRecentActivity(limit = 20): Promise<RecentLearningActivityList> {
  const { data, error } = await requireSupabase().rpc("get_student_recent_learning_activity", { p_limit: limit });
  return parseObject<RecentLearningActivityList>(data, error, "Recent learning activity");
}

export async function getStudentMasteryHistory(
  topicId: string,
  learningObjective?: string,
  limit = 50,
): Promise<StudentMasteryHistory> {
  const { data, error } = await requireSupabase().rpc("get_student_mastery_history", {
    p_topic_id: topicId,
    p_learning_objective: learningObjective ?? null,
    p_limit: limit,
  });
  return parseObject<StudentMasteryHistory>(data, error, "Mastery history");
}

export async function getStudentProgressComparison(periodDays = 30, topicId?: string): Promise<StudentProgressComparison> {
  const { data, error } = await requireSupabase().rpc("get_student_progress_comparison", {
    p_period_days: periodDays,
    p_topic_id: topicId ?? null,
  });
  return parseObject<StudentProgressComparison>(data, error, "Progress comparison");
}

export async function getClassLearningProgress(classId: string, topicId?: string): Promise<ClassLearningProgress> {
  const { data, error } = await requireSupabase().rpc("get_class_learning_progress", {
    p_class_id: classId,
    p_topic_id: topicId ?? null,
  });
  return parseObject<ClassLearningProgress>(data, error, "Class learning progress");
}
