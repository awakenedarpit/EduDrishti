import type { Json } from "../../lib/database.types";
import { AppError, friendlyBackendError } from "../../lib/backend-errors";
import { requireSupabase } from "../../lib/supabase";

export type QuestionType = "single_choice" | "multiple_choice" | "numeric" | "short_text";
export type ChoiceOption = { id: string; text: string };

export type AssessmentSummary = {
  assessment_id: string;
  title: string;
  description: string | null;
  assessment_type: "diagnostic" | "practice" | "summative";
  class_id: string | null;
  is_template: boolean;
  question_count: number;
  total_points: number;
  opens_at: string | null;
  closes_at: string | null;
};

export type AssessmentQuestion = {
  question_id: string;
  position: number;
  points: number;
  question_type: QuestionType;
  prompt: string;
  options: ChoiceOption[];
  difficulty: number;
  concept: string;
  topic: { id: string; code: string; title: string };
};

export type AssessmentEnvelope = {
  schema_version: number;
  assessment: {
    id: string;
    title: string;
    description: string | null;
    assessment_type: "diagnostic" | "practice" | "summative";
    class_id: string | null;
    is_template: boolean;
    opens_at: string | null;
    closes_at: string | null;
  };
  questions: AssessmentQuestion[];
};

export type AttemptRow = {
  id: string;
  assessment_id: string;
  attempt_number: number;
  status: "in_progress" | "submitted" | "graded" | "abandoned";
  started_at: string;
  submitted_at: string | null;
  score_percent: number | null;
};

export type SavedResponse = {
  question_id: string;
  answer: Json;
  is_answered: boolean;
};

export type ResultItem = {
  question_id: string;
  position: number;
  question_type: QuestionType;
  prompt: string;
  answer: Json;
  is_answered: boolean;
  is_correct: boolean;
  score_percent: number;
  points_earned: number;
  points_possible: number;
  correct_answer: Json;
  explanation: string | null;
  misconception_tags: string[];
};

export type AssessmentResult = {
  schema_version: number;
  attempt: {
    id: string;
    assessment_id: string;
    assessment_title: string;
    attempt_number: number;
    status: "graded";
    started_at: string;
    submitted_at: string;
    score_percent: number;
  };
  summary: {
    earned_points: number;
    total_points: number;
    correct_count: number;
    incorrect_count: number;
    unanswered_count: number;
  };
  items: ResultItem[];
};

export type TeacherClass = {
  id: string;
  name: string;
  grade_level: number;
  subject: string;
  description: string | null;
  created_at: string;
};

function requireData<T>(data: T | null, error: unknown): T {
  if (error) throw friendlyBackendError(error);
  if (data === null) throw new AppError("The database returned an empty response.");
  return data;
}

export async function listAvailableAssessments(): Promise<AssessmentSummary[]> {
  const { data, error } = await requireSupabase().rpc("list_available_assessments");
  const result = requireData(data, error);
  if (!Array.isArray(result)) throw new AppError("The assessment list had an unexpected format.");
  return result as unknown as AssessmentSummary[];
}

export async function getAssessment(assessmentId: string): Promise<AssessmentEnvelope> {
  const { data, error } = await requireSupabase().rpc("get_assessment", { p_assessment_id: assessmentId });
  const result = requireData(data, error) as unknown as AssessmentEnvelope;
  if (!result || !Array.isArray(result.questions) || !result.assessment) {
    throw new AppError("The assessment returned an unexpected format.");
  }
  return result;
}

export async function startAssessment(assessmentId: string): Promise<string> {
  const { data, error } = await requireSupabase().rpc("start_assessment", { p_assessment_id: assessmentId });
  return requireData(data, error);
}

export async function saveResponse(attemptId: string, questionId: string, answer: Json): Promise<string> {
  const { data, error } = await requireSupabase().rpc("save_response", {
    p_attempt_id: attemptId,
    p_question_id: questionId,
    p_answer: answer,
  });
  return requireData(data, error);
}

export async function completeAssessment(attemptId: string): Promise<AssessmentResult> {
  const { data, error } = await requireSupabase().rpc("complete_assessment", { p_attempt_id: attemptId });
  return requireData(data, error) as unknown as AssessmentResult;
}

export async function getStudentResults(attemptId: string): Promise<AssessmentResult> {
  const { data, error } = await requireSupabase().rpc("get_student_results", { p_attempt_id: attemptId });
  return requireData(data, error) as unknown as AssessmentResult;
}

export async function getMyAttempt(attemptId: string): Promise<AttemptRow> {
  const { data, error } = await requireSupabase()
    .from("assessment_attempts")
    .select("id, assessment_id, attempt_number, status, started_at, submitted_at, score_percent")
    .eq("id", attemptId)
    .maybeSingle();
  if (error) throw friendlyBackendError(error);
  if (!data) throw new AppError("This attempt could not be found for the signed-in account.");
  return data;
}

export async function listMyAttempts(): Promise<AttemptRow[]> {
  const { data, error } = await requireSupabase()
    .from("assessment_attempts")
    .select("id, assessment_id, attempt_number, status, started_at, submitted_at, score_percent")
    .order("started_at", { ascending: false });
  return requireData(data, error);
}

export async function listAttemptResponses(attemptId: string): Promise<SavedResponse[]> {
  const { data, error } = await requireSupabase()
    .from("responses")
    .select("question_id, answer, is_answered")
    .eq("attempt_id", attemptId);
  return requireData(data, error);
}

export async function listTeacherClasses(): Promise<TeacherClass[]> {
  const { data, error } = await requireSupabase()
    .from("classes")
    .select("id, name, grade_level, subject, description, created_at")
    .order("created_at", { ascending: false });
  return requireData(data, error);
}

export async function createTeacherClass(input: {
  name: string;
  gradeLevel: number;
  subject: string;
  description: string;
}): Promise<string> {
  const { data, error } = await requireSupabase().rpc("create_class", {
    p_name: input.name.trim(),
    p_grade_level: input.gradeLevel,
    p_subject: input.subject.trim(),
    p_description: input.description.trim() || null,
  });
  return requireData(data, error);
}
