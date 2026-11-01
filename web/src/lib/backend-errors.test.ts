import { describe, expect, it } from "vitest";
import { friendlyBackendError, normalizeApiError } from "./backend-errors";

describe("normalizeApiError", () => {
  it.each([
    [{ code: "28000", message: "Authentication is required" }, "unauthenticated", 401],
    [{ code: "42501", message: "foreign class" }, "forbidden", 403],
    [{ status: 404, error: { code: "practice_set_not_found", message: "missing" } }, "not_found", 404],
    [{ code: "22023", message: "invalid answer" }, "validation_failed", 400],
    [{ status: 409, error: { code: "graded_attempt_required" } }, "conflict", 409],
    [{ status: 429, error: { code: "rate_limited" } }, "rate_limited", 429],
    [{ code: "PGRST202", message: "missing function" }, "capability_unavailable", 503],
    [{ status: 503, error: { code: "ai_unavailable" } }, "service_unavailable", 503],
    [{ status: 500, message: "internal" }, "server_error", 500],
  ] as const)("maps %j to %s", (input, category, status) => {
    const result = normalizeApiError(input);
    expect(result.category).toBe(category);
    expect(result.httpStatus).toBe(status);
  });

  it("marks transient categories retryable and validation errors non-retryable", () => {
    expect(normalizeApiError({ status: 429, error: { code: "rate_limited" } }).retryable).toBe(true);
    expect(normalizeApiError({ status: 503, code: "service_unavailable" }).retryable).toBe(true);
    expect(normalizeApiError({ code: "22023" }).retryable).toBe(false);
  });

  it("does not expose database details or hints as UI copy", () => {
    const result = normalizeApiError({
      code: "22023",
      message: "invalid user-supplied payload",
      details: "sensitive database detail",
      hint: "internal SQL hint",
    });
    expect(result.message).not.toContain("sensitive");
    expect(result.message).not.toContain("internal SQL");
    expect(result).not.toHaveProperty("details");
    expect(result).not.toHaveProperty("hint");
  });

  it("preserves the legacy friendly mapper's established messages", () => {
    expect(friendlyBackendError({ code: "55000" }).message).toContain("no longer in an editable state");
    expect(friendlyBackendError({ code: "23505" }).message).toContain("already exists");
  });
});
