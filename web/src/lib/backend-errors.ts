export type BackendErrorLike = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
};

export class AppError extends Error {
  readonly code?: string;
  readonly original?: unknown;

  constructor(message: string, options?: { code?: string; original?: unknown }) {
    super(message);
    this.name = "AppError";
    this.code = options?.code;
    this.original = options?.original;
  }
}

export function friendlyBackendError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const value = error as BackendErrorLike;
  const code = typeof value?.code === "string" ? value.code : undefined;

  if (code === "28000" || code === "PGRST301") {
    return new AppError("Your session has expired. Sign in again to continue.", { code, original: error });
  }
  if (code === "42501") {
    return new AppError("This account is not authorized for that action or record.", { code, original: error });
  }
  if (code === "22023") {
    return new AppError("The submitted answer or request is not valid. Please review it and try again.", { code, original: error });
  }
  if (code === "55000") {
    return new AppError("This assessment is no longer in an editable state. Refresh the page to see the latest status.", { code, original: error });
  }
  if (code === "PGRST202" || code === "PGRST204" || code === "42883") {
    return new AppError("This capability is not installed in the connected database yet.", { code, original: error });
  }
  if (code === "23505") {
    return new AppError("A record with these details already exists. Try a different name.", { code, original: error });
  }
  if (code === "23514") {
    return new AppError("Some information does not meet the database requirements. Check the form and retry.", { code, original: error });
  }

  const message = typeof value?.message === "string" ? value.message : "A connection error occurred.";
  if (/network|fetch|timeout|offline/i.test(message)) {
    return new AppError("Could not reach Supabase. Check your connection and try again.", { code, original: error });
  }
  return new AppError("EduDrishti could not complete that request. Please try again.", { code, original: error });
}
