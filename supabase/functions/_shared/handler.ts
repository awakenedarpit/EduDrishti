import { GeminiServiceError } from "./gemini.ts";
import { buildExplanationPrompt, buildPracticePrompt, PROMPT_VERSION, type DiagnosisContext, type LearningContext, type PracticeOperation } from "./prompts.ts";
import {
  isPracticeItem,
  OutputValidationError,
  sanitizePracticeItem,
  validateExplanation,
  validatePracticeAnswer,
  validatePracticeOutput,
  type ExplanationOutput,
  type JsonObject,
  type PracticeItem,
} from "./validators.ts";

export type ServiceName = "explanation" | "practice" | "practice_answer";
export type ServiceKind = "explanation" | "practice" | "practice_answer";

export interface AuthSession {
  userId: string;
  accessToken: string;
}

export interface AssessmentItem {
  question_id: string;
  question_type: string;
  prompt: string;
  answer: unknown;
  is_answered: boolean;
  is_correct: boolean;
  correct_answer: unknown;
  explanation: string;
}

export interface AssessmentResult {
  attempt: { id: string; assessment_id: string; status: string };
  items: AssessmentItem[];
}

export interface DiagnosisRow {
  topic_id: string;
  misconception_code: string;
  summary: string;
  evidence: { rule_based?: boolean; matches?: Array<Record<string, unknown>> };
}

export interface QuestionMetadata {
  topic: { title: string; subject: string; grade_level: number; code: string };
  concept: string | null;
  difficulty: number | null;
}

export interface StoredActivity {
  id: string;
  activity_type: string;
  content: unknown;
  model: string;
  prompt_version: string;
}

export interface ServiceDependencies {
  allowedOrigins: string[];
  model: string;
  authenticate(request: Request): Promise<AuthSession>;
  consumeRateLimit(userId: string, service: ServiceName): Promise<boolean>;
  getAssessmentResult(accessToken: string, attemptId: string): Promise<AssessmentResult>;
  getDiagnoses(accessToken: string, attemptId: string): Promise<DiagnosisRow[]>;
  getQuestionMetadata(userId: string, attemptId: string, questionId: string): Promise<QuestionMetadata>;
  generate(prompt: ReturnType<typeof buildExplanationPrompt> | ReturnType<typeof buildPracticePrompt>, maxTokens: number): Promise<unknown>;
  saveActivity(args: {
    userId: string;
    attemptId: string;
    questionId: string;
    activityType: "explanation" | "practice";
    content: ExplanationOutput | { schema_version: number; items: PracticeItem[] };
    model: string;
    promptVersion: string;
  }): Promise<string>;
  getActivity(userId: string, activityId: string): Promise<StoredActivity | null>;
  savePracticeResponse(args: {
    userId: string;
    activityId: string;
    itemId: string;
    answer: { selected_option: string };
  }): Promise<boolean>;
  logFailure?(service: ServiceKind, code: string): void;
  idFactory?: () => string;
}

class ServiceError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message = code) {
    super(message);
    this.name = "ServiceError";
    this.status = status;
    this.code = code;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const MAX_BODY_BYTES = 8_192;

function jsonResponse(status: number, body: unknown, origin: string | null, allowed: boolean): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
  });
  if (origin && allowed) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
    headers.set("access-control-allow-headers", "authorization, apikey, content-type, x-client-info");
    headers.set("access-control-allow-methods", "POST, OPTIONS");
    headers.set("access-control-max-age", "600");
  }
  return status === 204 ? new Response(null, { status, headers }) : new Response(JSON.stringify(body), { status, headers });
}

async function readJsonLimited(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type")?.split(";")[0].trim().toLowerCase();
  if (contentType !== "application/json") throw new ServiceError(415, "content_type_required");
  const length = Number(request.headers.get("content-length"));
  if (Number.isFinite(length) && length > MAX_BODY_BYTES) throw new ServiceError(413, "request_too_large");
  if (!request.body) throw new ServiceError(400, "invalid_request");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new ServiceError(413, "request_too_large");
    }
    chunks.push(value);
  }
  const text = new TextDecoder("utf-8", { fatal: true }).decode(
    chunks.reduce((all, chunk) => {
      const merged = new Uint8Array(all.length + chunk.length);
      merged.set(all);
      merged.set(chunk, all.length);
      return merged;
    }, new Uint8Array()),
  );
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new ServiceError(400, "invalid_json");
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function strictBody(value: unknown, allowedKeys: string[], requiredKeys: string[]): JsonObject {
  if (!isObject(value)) throw new ServiceError(400, "invalid_request");
  const keys = Object.keys(value);
  if (keys.some((key) => !allowedKeys.includes(key)) || requiredKeys.some((key) => !(key in value))) {
    throw new ServiceError(400, "invalid_request");
  }
  return value;
}

function uuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) throw new ServiceError(400, `invalid_${field}`);
  return value;
}

function answerSummary(item: AssessmentItem): string {
  if (!item.is_answered) return "No answer was submitted.";
  if (!isObject(item.answer)) return "A submitted response was recorded; its content is omitted.";
  if (item.question_type === "single_choice" && typeof item.answer.selected_option === "string") {
    return `Selected option ${item.answer.selected_option}.`;
  }
  if (item.question_type === "multiple_choice" && Array.isArray(item.answer.selected_options)) {
    const selections = item.answer.selected_options.filter((entry): entry is string => typeof entry === "string").slice(0, 8);
    return `Selected options: ${selections.join(", ")}.`;
  }
  if (item.question_type === "numeric" && typeof item.answer.value === "number" && Number.isFinite(item.answer.value)) {
    return `Numeric response: ${item.answer.value}.`;
  }
  return "A short-text response was recorded but is omitted to avoid sending free-form personal data to the AI provider.";
}

function matchingDiagnosis(rows: DiagnosisRow[], questionId: string): DiagnosisContext | null {
  for (const row of rows) {
    if (row.evidence?.rule_based !== true || !Array.isArray(row.evidence.matches)) continue;
    const match = row.evidence.matches.find((entry) => entry.question_id === questionId);
    if (!match) continue;
    return {
      code: row.misconception_code.slice(0, 100),
      summary: row.summary.slice(0, 300),
      corrective_example: typeof match.corrective_example === "string" ? match.corrective_example.slice(0, 500) : null,
      followup_question: typeof match.followup_question === "string" ? match.followup_question.slice(0, 250) : null,
      source: "rule_based",
    };
  }
  return null;
}

function practiceOperation(metadata: QuestionMetadata): PracticeOperation | null {
  if (metadata.topic.code !== "quadratic-equations" || metadata.topic.subject !== "Mathematics" || metadata.topic.grade_level !== 10) {
    return null;
  }
  if (typeof metadata.concept !== "string") return null;
  if (/^discriminant(?:_|$)/u.test(metadata.concept)) return "discriminant";
  if (metadata.concept === "factorisation_roots") return "roots";
  return null;
}

function fallback(item: AssessmentItem, diagnosis: DiagnosisContext | null): JsonObject {
  return {
    source: "existing_assessment_guidance",
    original_explanation: item.explanation,
    rule_based_diagnosis: diagnosis,
    corrective_example: diagnosis?.corrective_example ?? null,
    followup_question: diagnosis?.followup_question ?? null,
  };
}

function safeError(error: unknown): { status: number; code: string } {
  if (error instanceof ServiceError) return { status: error.status, code: error.code };
  if (error instanceof GeminiServiceError) return { status: error.status, code: error.code };
  if (typeof error === "object" && error !== null && "status" in error && "code" in error) {
    const candidate = error as { status: unknown; code: unknown };
    if (typeof candidate.status === "number" && typeof candidate.code === "string") {
      return { status: candidate.status, code: candidate.code };
    }
  }
  return { status: 503, code: "service_unavailable" };
}

function modelUnavailable(error: unknown): boolean {
  return error instanceof GeminiServiceError || error instanceof OutputValidationError;
}

export function createAIHandler(kind: ServiceKind, deps: ServiceDependencies): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get("origin");
    const originAllowed = !origin || deps.allowedOrigins.includes(origin);
    if (request.method === "OPTIONS") {
      if (!originAllowed) return jsonResponse(403, { error: { code: "origin_not_allowed" } }, null, false);
      return jsonResponse(204, {}, origin, true);
    }
    if (origin && !originAllowed) return jsonResponse(403, { error: { code: "origin_not_allowed" } }, null, false);
    if (request.method !== "POST") return jsonResponse(405, { error: { code: "method_not_allowed" } }, origin, originAllowed);

    try {
      if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) throw new ServiceError(413, "request_too_large");
      const session = await deps.authenticate(request);
      const raw = await readJsonLimited(request);

      if (kind === "practice_answer") {
        const body = strictBody(raw, ["activity_id", "item_id", "answer"], ["activity_id", "item_id", "answer"]);
        const activityId = uuid(body.activity_id, "activity_id");
        const itemId = uuid(body.item_id, "item_id");
        if (!(await deps.consumeRateLimit(session.userId, "practice_answer"))) throw new ServiceError(429, "rate_limited");
        const activity = await deps.getActivity(session.userId, activityId);
        if (!activity || activity.activity_type !== "practice" || !isObject(activity.content) || !Array.isArray(activity.content.items)) {
          throw new ServiceError(404, "practice_set_not_found");
        }
        const item = activity.content.items.find((candidate) => isPracticeItem(candidate) && candidate.id === itemId);
        if (!isPracticeItem(item)) throw new ServiceError(404, "practice_item_not_found");
        let answer: { selected_option: string };
        try {
          answer = validatePracticeAnswer(body.answer, item);
        } catch {
          throw new ServiceError(400, "invalid_answer");
        }
        const isCorrect = await deps.savePracticeResponse({
          userId: session.userId,
          activityId,
          itemId,
          answer,
        });
        return jsonResponse(200, {
          source: "ai_generated",
          is_correct: isCorrect,
          feedback: item.explanation,
          correct_answer: item.correct_answer,
        }, origin, originAllowed);
      }

      const allowedKeys = kind === "practice" ? ["attempt_id", "question_id", "count"] : ["attempt_id", "question_id"];
      const body = strictBody(raw, allowedKeys, ["attempt_id", "question_id"]);
      const attemptId = uuid(body.attempt_id, "attempt_id");
      const questionId = uuid(body.question_id, "question_id");
      const count = kind === "practice" ? (body.count === undefined ? 2 : body.count) : undefined;
      if (kind === "practice" && (typeof count !== "number" || !Number.isInteger(count) || count < 1 || count > 3)) {
        throw new ServiceError(400, "invalid_count");
      }
      const serviceName: ServiceName = kind === "practice" ? "practice" : "explanation";
      if (!(await deps.consumeRateLimit(session.userId, serviceName))) throw new ServiceError(429, "rate_limited");

      const result = await deps.getAssessmentResult(session.accessToken, attemptId);
      if (result.attempt?.id !== attemptId || result.attempt.status !== "graded" || !Array.isArray(result.items)) {
        throw new ServiceError(409, "graded_attempt_required");
      }
      const item = result.items.find((candidate) => candidate.question_id === questionId);
      if (!item) throw new ServiceError(404, "question_not_in_attempt");
      if (!item.is_answered) throw new ServiceError(409, "answered_question_required");
      const diagnoses = await deps.getDiagnoses(session.accessToken, attemptId);
      const diagnosis = matchingDiagnosis(diagnoses, questionId);
      if (kind === "practice" && item.is_correct && !diagnosis) throw new ServiceError(409, "learning_target_not_identified");
      const metadata = await deps.getQuestionMetadata(session.userId, attemptId, questionId);
      const operation = kind === "practice" ? practiceOperation(metadata) : undefined;
      if (kind === "practice" && (
        !operation
        || typeof metadata.difficulty !== "number"
        || !Number.isInteger(metadata.difficulty)
        || metadata.difficulty < 1
        || metadata.difficulty > 5
      )) {
        throw new ServiceError(409, "unsupported_practice_target");
      }
      const context: LearningContext = {
        topic: {
          title: metadata.topic.title.slice(0, 120),
          subject: metadata.topic.subject.slice(0, 80),
          grade_level: metadata.topic.grade_level,
          code: metadata.topic.code.slice(0, 100),
        },
        concept: metadata.concept?.slice(0, 240) ?? null,
        difficulty: metadata.difficulty,
        question_type: item.question_type,
        prompt: item.prompt.slice(0, 2_000),
        answer_summary: answerSummary(item),
        was_correct: item.is_correct,
        diagnosis,
      };

      if (kind === "explanation") {
        let content: ExplanationOutput;
        try {
          content = validateExplanation(await deps.generate(buildExplanationPrompt(context), 1_100));
        } catch (error) {
          if (!modelUnavailable(error)) throw error;
          deps.logFailure?.(kind, safeError(error).code);
          return jsonResponse(503, {
            error: { code: "ai_unavailable", message: "The AI explanation is unavailable right now." },
            fallback: fallback(item, diagnosis),
            source: "existing_assessment_guidance",
          }, origin, originAllowed);
        }
        const activityId = await deps.saveActivity({
          userId: session.userId,
          attemptId,
          questionId,
          activityType: "explanation",
          content,
          model: deps.model,
          promptVersion: PROMPT_VERSION,
        });
        return jsonResponse(200, {
          activity_id: activityId,
          source: "ai_generated",
          model: deps.model,
          prompt_version: PROMPT_VERSION,
          explanation: content,
          rule_based_diagnosis: diagnosis,
        }, origin, originAllowed);
      }

      let items: PracticeItem[];
      try {
        const rawOutput = await deps.generate(buildPracticePrompt(context, count as number, operation as PracticeOperation), 1_700);
        items = validatePracticeOutput(
          rawOutput,
          count as number,
          metadata.topic.title,
          deps.idFactory ?? (() => crypto.randomUUID()),
          operation as PracticeOperation,
          metadata.difficulty as number,
        );
      } catch (error) {
        if (!modelUnavailable(error)) throw error;
        deps.logFailure?.(kind, safeError(error).code);
        return jsonResponse(503, {
          error: { code: "ai_unavailable", message: "AI-generated practice is unavailable right now." },
          fallback: fallback(item, diagnosis),
          source: "existing_assessment_guidance",
        }, origin, originAllowed);
      }
      const storedId = await deps.saveActivity({
        userId: session.userId,
        attemptId,
        questionId,
        activityType: "practice",
        content: { schema_version: 1, items },
        model: deps.model,
        promptVersion: PROMPT_VERSION,
      });
      return jsonResponse(200, {
        activity_id: storedId,
        source: "ai_generated",
        model: deps.model,
        prompt_version: PROMPT_VERSION,
        topic: metadata.topic,
        items: items.map(sanitizePracticeItem),
        answer_policy: "Submit an answer to check-practice-answer to receive feedback and the answer key.",
        rule_based_diagnosis: diagnosis,
      }, origin, originAllowed);
    } catch (error) {
      const mapped = safeError(error);
      deps.logFailure?.(kind, mapped.code);
      return jsonResponse(mapped.status, {
        error: { code: mapped.code, message: publicMessage(mapped.code) },
      }, origin, originAllowed);
    }
  };
}

function publicMessage(code: string): string {
  switch (code) {
    case "rate_limited": return "The request limit has been reached. Try again later.";
    case "graded_attempt_required": return "A completed assessment is required.";
    case "learning_target_not_identified": return "This question does not identify a learning target yet.";
    case "unsupported_practice_target": return "Targeted practice is not available for this skill yet.";
    case "question_not_in_attempt": return "The question is not part of this assessment attempt.";
    case "answered_question_required": return "Answer the question before requesting personalized support.";
    case "unauthenticated": return "Sign in to use this service.";
    case "not_authorized": return "This service is available to student accounts only.";
    case "invalid_request":
    case "invalid_attempt_id":
    case "invalid_question_id":
    case "invalid_activity_id":
    case "invalid_item_id":
    case "invalid_count":
    case "invalid_answer": return "The request is invalid.";
    default: return code === "service_unavailable" ? "The service is temporarily unavailable." : "The request could not be completed.";
  }
}
