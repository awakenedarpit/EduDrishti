import type { Database, Json } from "./database.types";

export type AppRole = "student" | "teacher";
export type AssessmentType = "diagnostic" | "practice" | "summative";
export type AttemptStatus = "in_progress" | "submitted" | "graded" | "abandoned";
export type QuestionType = "single_choice" | "multiple_choice" | "numeric" | "short_text";

/** Client-normalized categories. Raw PostgREST and Edge Function errors are not identical on the wire. */
export type ApiErrorCategory =
  | "unauthenticated"
  | "forbidden"
  | "not_found"
  | "validation_failed"
  | "conflict"
  | "rate_limited"
  | "capability_unavailable"
  | "service_unavailable"
  | "server_error"
  | "unknown";

/** Safe, presentation-ready error; raw database details/hints must not be shown to learners. */
export interface ApiError {
  category: ApiErrorCategory;
  code: string;
  message: string;
  httpStatus: number;
  retryable: boolean;
  requestId?: string;
  fieldErrors?: Record<string, string[]>;
}

/** Edge Function wire envelope. The `error` object is present for non-success responses. */
export interface EdgeFunctionErrorEnvelope {
  error: { code: string; message: string };
}

/** Supabase/PostgREST error envelope; `details` and `hint` are diagnostic, not UI copy. */
export interface PostgrestErrorEnvelope {
  code: string;
  message: string;
  details: string | null;
  hint: string | null;
}

export type EmptyStateReason = "no_records" | "no_assessments" | "no_scored_evidence" | "insufficient_evidence";

/** Discriminated state model for integration components; empty data is not an error. */
export type RequestState<T> =
  | { status: "loading" }
  | { status: "success"; data: T }
  | { status: "empty"; data: T; reason: EmptyStateReason }
  | { status: "error"; error: ApiError };

export type AssessmentAnswer =
  | { selected_option: string }
  | { selected_options: string[] }
  | { value: string | number };

export interface SaveResponseRequest {
  p_attempt_id: string;
  p_question_id: string;
  p_answer: Json;
}

export interface TeacherClassSummary {
  id: string;
  name: string;
  grade_level: number;
  subject: string;
  description: string | null;
  created_at: string;
}

export interface AssessmentSummary {
  assessment_id: string;
  title: string;
  description: string | null;
  assessment_type: AssessmentType;
  class_id: string | null;
  is_template: boolean;
  question_count: number;
  total_points: number;
  opens_at: string | null;
  closes_at: string | null;
}

/** Type-safe request/result lookup for generated Supabase Database RPC declarations. */
type PublicFunctions = Database["public"]["Functions"];
export type RpcName = keyof PublicFunctions;
export type RpcArgs<Name extends RpcName> = PublicFunctions[Name]["Args"];
export type RpcResult<Name extends RpcName> = PublicFunctions[Name]["Returns"];

/** Stage 4 Edge Function source contracts; deployment is tracked separately in the integration guide. */
export interface PersonalizedExplanationRequest {
  attempt_id: string;
  question_id: string;
}

export interface TargetedPracticeRequest extends PersonalizedExplanationRequest {
  count?: 1 | 2 | 3;
}

export interface CheckPracticeAnswerRequest {
  activity_id: string;
  item_id: string;
  answer: { selected_option: string };
}
