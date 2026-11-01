import type { ApiError, ApiErrorCategory } from "./api-contracts";

export type BackendErrorLike = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
  status?: number;
  statusCode?: number;
  request_id?: string;
  requestId?: string;
  error?: { code?: string; message?: string };
};

export class AppError extends Error {
  readonly code?: string;
  readonly original?: unknown;
  readonly category: ApiErrorCategory;
  readonly httpStatus: number;
  readonly retryable: boolean;

  constructor(message: string, options?: {
    code?: string;
    original?: unknown;
    category?: ApiErrorCategory;
    httpStatus?: number;
    retryable?: boolean;
  }) {
    super(message);
    this.name = "AppError";
    this.code = options?.code;
    this.original = options?.original;
    this.category = options?.category ?? "unknown";
    this.httpStatus = options?.httpStatus ?? 500;
    this.retryable = options?.retryable ?? false;
  }
}

type ErrorFacts = {
  code?: string;
  status?: number;
  message?: string;
  requestId?: string;
};

function errorFacts(error: unknown): ErrorFacts {
  if (typeof error !== "object" || error === null) return {};
  const value = error as BackendErrorLike;
  const nested = value.error;
  const code = typeof nested?.code === "string" ? nested.code : value.code;
  const status = Number.isInteger(value.status) ? value.status : value.statusCode;
  return {
    code: typeof code === "string" ? code : undefined,
    status: Number.isInteger(status) ? status : undefined,
    message: typeof nested?.message === "string" ? nested.message : value.message,
    requestId: typeof value.request_id === "string" ? value.request_id : value.requestId,
  };
}

function classify(facts: ErrorFacts): ApiErrorCategory {
  const code = facts.code ?? "";
  const status = facts.status;
  if (code === "28000" || code === "PGRST301" || code === "unauthenticated" || status === 401) return "unauthenticated";
  if (code === "42501" || code === "not_authorized" || code === "forbidden" || code === "origin_not_allowed" || status === 403) return "forbidden";
  if (code === "P0002" || code === "02000" || code === "PGRST116" || code === "not_found"
    || code.endsWith("_not_found") || code.endsWith("_not_in_attempt") || status === 404) return "not_found";
  if (code === "rate_limited" || code === "provider_rate_limited" || status === 429) return "rate_limited";
  if (["PGRST202", "PGRST204", "42883", "capability_unavailable"].includes(code)) return "capability_unavailable";
  if (code === "23505" || code === "55000" || code === "graded_attempt_required" || status === 409) return "conflict";
  if (["22023", "23514", "PGRST100", "PGRST102", "invalid_request", "invalid_json", "invalid_answer"].includes(code)
    || [400, 413, 415, 422].includes(status ?? 0)) return "validation_failed";
  if (status !== undefined && status >= 500) return status === 503 ? "service_unavailable" : "server_error";
  if (/network|fetch|timeout|offline/i.test(facts.message ?? "")) return "service_unavailable";
  return "unknown";
}

function statusFor(category: ApiErrorCategory, provided?: number): number {
  if (provided && provided >= 400 && provided <= 599) return provided;
  switch (category) {
    case "unauthenticated": return 401;
    case "forbidden": return 403;
    case "not_found": return 404;
    case "validation_failed": return 400;
    case "conflict": return 409;
    case "rate_limited": return 429;
    case "capability_unavailable":
    case "service_unavailable": return 503;
    case "server_error": return 500;
    default: return 500;
  }
}

const safeMessages: Record<ApiErrorCategory, string> = {
  unauthenticated: "Your session has expired. Sign in again to continue.",
  forbidden: "This account is not authorized for that action or record.",
  not_found: "The requested item could not be found.",
  validation_failed: "The request is invalid. Review the information and try again.",
  conflict: "This action is not available in the current state. Refresh and try again.",
  rate_limited: "The request limit has been reached. Try again later.",
  capability_unavailable: "This capability is not installed in the connected database yet.",
  service_unavailable: "The service is temporarily unavailable. Check your connection and try again.",
  server_error: "EduDrishti could not complete that request. Please try again.",
  unknown: "EduDrishti could not complete that request. Please try again.",
};

/** Normalize either the Supabase/PostgREST SQLSTATE envelope or an Edge Function envelope. */
export function normalizeApiError(error: unknown): ApiError {
  const facts = errorFacts(error);
  const category = classify(facts);
  return {
    category,
    code: facts.code ?? "unknown",
    message: safeMessages[category],
    httpStatus: statusFor(category, facts.status),
    retryable: category === "rate_limited" || category === "service_unavailable" || category === "server_error",
    ...(facts.requestId ? { requestId: facts.requestId } : {}),
  };
}

/** Legacy UI adapter. Existing message/code behavior is retained where it was already defined. */
export function friendlyBackendError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const facts = errorFacts(error);
  const normalized = normalizeApiError(error);
  const code = facts.code;
  let message = normalized.message;

  if (code === "22023") message = "The submitted answer or request is not valid. Please review it and try again.";
  else if (code === "55000") message = "This assessment is no longer in an editable state. Refresh the page to see the latest status.";
  else if (code === "23505") message = "A record with these details already exists. Try a different name.";
  else if (code === "23514") message = "Some information does not meet the database requirements. Check the form and retry.";

  return new AppError(message, {
    code: code ?? "unknown",
    original: error,
    category: normalized.category,
    httpStatus: normalized.httpStatus,
    retryable: normalized.retryable,
  });
}
