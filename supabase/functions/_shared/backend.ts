import { generateGeminiJson, GeminiServiceError, type GeminiPrompt } from "./gemini.ts";
import type { ServiceDependencies, ServiceName, StoredActivity, AssessmentResult, DiagnosisRow, QuestionMetadata } from "./handler.ts";

export type EnvGetter = (name: string) => string | undefined;

class BackendError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string) {
    super(code);
    this.name = "BackendError";
    this.status = status;
    this.code = code;
  }
}

function required(env: EnvGetter, name: string): string {
  const value = env(name)?.trim();
  if (!value) throw new BackendError(503, "service_configuration_missing");
  return value;
}

function keyFromMap(raw: string | undefined, keyName: string): string | undefined {
  if (!raw) return undefined;
  try {
    const value = JSON.parse(raw) as Record<string, unknown>;
    const key = value[keyName];
    return typeof key === "string" && key.length > 0 ? key : undefined;
  } catch {
    return undefined;
  }
}

function supabaseUrl(env: EnvGetter): string {
  const raw = required(env, "SUPABASE_URL");
  try {
    const url = new URL(raw);
    if (!new Set(["https:", "http:"]).has(url.protocol) || url.username || url.password) throw new Error();
    return url.origin;
  } catch {
    throw new BackendError(503, "service_configuration_invalid");
  }
}

function publishableKey(env: EnvGetter): string {
  const key = keyFromMap(env("SUPABASE_PUBLISHABLE_KEYS"), "default")
    ?? env("SUPABASE_PUBLISHABLE_KEY")
    ?? env("SUPABASE_ANON_KEY");
  if (!key?.trim()) throw new BackendError(503, "service_configuration_missing");
  return key.trim();
}

function secretKey(env: EnvGetter): string {
  const key = keyFromMap(env("SUPABASE_SECRET_KEYS"), "default")
    ?? env("SUPABASE_SECRET_KEY")
    ?? env("SUPABASE_SERVICE_ROLE_KEY");
  if (!key?.trim()) throw new BackendError(503, "service_configuration_missing");
  return key.trim();
}

async function readJson(response: Response): Promise<unknown> {
  const maxBytes = 150_000;
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new BackendError(502, "service_response_too_large");
  }
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new BackendError(502, "service_response_too_large");
    }
    chunks.push(value);
  }
  const combined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(combined)) as unknown;
  } catch {
    return null;
  }
}

function providerErrorCode(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const code = (body as Record<string, unknown>).code;
  return typeof code === "string" ? code : null;
}

function httpError(status: number, code: string): BackendError {
  if (status === 401 || code === "28000") return new BackendError(401, "unauthenticated");
  if (status === 403 || code === "42501") return new BackendError(403, "not_authorized");
  if (code === "55000") return new BackendError(409, "graded_attempt_required");
  return new BackendError(503, "service_unavailable");
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

export function createServiceDependencies(env: EnvGetter, fetcher: typeof fetch = fetch): ServiceDependencies {
  const url = () => supabaseUrl(env);
  const anon = () => publishableKey(env);
  const service = () => secretKey(env);
  const model = (env("GEMINI_MODEL")?.trim() || "gemini-3.8-flash");
  const allowedOrigins = (env("AI_ALLOWED_ORIGINS") || "http://localhost:3000,http://127.0.0.1:3000")
    .split(",").map((origin) => origin.trim()).filter(Boolean);

  async function boundedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    try {
      return await fetcher(input, { ...init, signal: AbortSignal.timeout(5_000) });
    } catch {
      throw new BackendError(503, "service_unavailable");
    }
  }

  async function rpc<T>(name: string, args: Record<string, unknown>, options: {
    accessToken?: string;
    admin?: boolean;
  } = {}): Promise<T> {
    const key = options.admin ? service() : anon();
    if (!options.admin && !options.accessToken) throw new BackendError(401, "unauthenticated");
    const headers = new Headers({
      apikey: key,
      "content-type": "application/json",
      accept: "application/json",
    });
    if (options.admin) {
      // New secret keys are API keys, not JWTs; they must never be sent as Bearer tokens.
      if (!key.startsWith("sb_secret_")) headers.set("authorization", `Bearer ${key}`);
    } else {
      headers.set("authorization", `Bearer ${options.accessToken}`);
    }
    let response: Response;
    try {
      response = await boundedFetch(`${url()}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers,
        body: JSON.stringify(args),
      });
    } catch {
      throw new BackendError(503, "service_unavailable");
    }
    const body = await readJson(response);
    if (!response.ok) {
      if (name === "get_student_diagnoses" && (response.status === 404 || providerErrorCode(body) === "42883")) {
        return null as T;
      }
      throw httpError(response.status, providerErrorCode(body) ?? "");
    }
    return body as T;
  }

  return {
    allowedOrigins,
    model,
    async authenticate(request) {
      const header = request.headers.get("authorization") ?? "";
      const match = /^Bearer\s+([A-Za-z0-9._~-]{20,8192})$/u.exec(header);
      if (!match) throw new BackendError(401, "unauthenticated");
      const accessToken = match[1];
      let response: Response;
      try {
        response = await boundedFetch(`${url()}/auth/v1/user`, {
          headers: { apikey: anon(), authorization: `Bearer ${accessToken}` },
        });
      } catch {
        throw new BackendError(503, "service_unavailable");
      }
      if (!response.ok) throw new BackendError(401, "unauthenticated");
      const user = record(await readJson(response));
      if (typeof user?.id !== "string" || !/^[0-9a-f-]{36}$/iu.test(user.id)) {
        throw new BackendError(401, "unauthenticated");
      }
      let profileResponse: Response;
      try {
        const profileUrl = new URL(`${url()}/rest/v1/profiles`);
        profileUrl.searchParams.set("select", "app_role");
        profileUrl.searchParams.set("user_id", `eq.${user.id}`);
        profileUrl.searchParams.set("limit", "1");
        profileResponse = await boundedFetch(profileUrl, {
          headers: { apikey: anon(), authorization: `Bearer ${accessToken}`, accept: "application/json" },
        });
      } catch {
        throw new BackendError(503, "service_unavailable");
      }
      if (!profileResponse.ok) throw new BackendError(503, "service_unavailable");
      const profiles = await readJson(profileResponse);
      const profile = Array.isArray(profiles) ? record(profiles[0]) : null;
      if (profile?.app_role !== "student") throw new BackendError(403, "not_authorized");
      return { userId: user.id, accessToken };
    },
    async consumeRateLimit(userId: string, serviceName: ServiceName) {
      try {
        const allowed = await rpc<boolean>("consume_ai_request", {
          p_student_id: userId,
          p_service_name: serviceName,
        }, { admin: true });
        return allowed === true;
      } catch {
        throw new BackendError(503, "service_unavailable");
      }
    },
    async getAssessmentResult(accessToken: string, attemptId: string) {
      const result = await rpc<AssessmentResult>("get_student_results", { p_attempt_id: attemptId }, { accessToken });
      if (!result || typeof result !== "object") throw new BackendError(409, "graded_attempt_required");
      return result;
    },
    async getDiagnoses(accessToken: string, attemptId: string) {
      const response = await rpc<{ diagnoses?: DiagnosisRow[] }>("get_student_diagnoses", { p_attempt_id: attemptId }, { accessToken });
      return Array.isArray(response?.diagnoses) ? response.diagnoses : [];
    },
    async getQuestionMetadata(userId: string, attemptId: string, questionId: string) {
      const response = await rpc<QuestionMetadata>("get_ai_learning_context", {
        p_student_id: userId,
        p_attempt_id: attemptId,
        p_question_id: questionId,
      }, { admin: true });
      if (!response || typeof response !== "object" || !response.topic) throw new BackendError(503, "service_unavailable");
      return response;
    },
    async generate(prompt, maxTokens) {
      const geminiKey = env("GEMINI_API_KEY")?.trim();
      if (!geminiKey) throw new GeminiServiceError("provider_not_configured", 503);
      return await generateGeminiJson({
        apiKey: geminiKey,
        model,
        fetcher,
        timeoutMs: 12_000,
      }, prompt as GeminiPrompt, maxTokens);
    },
    async saveActivity(args) {
      const id = await rpc<string>("store_ai_learning_activity", {
        p_student_id: args.userId,
        p_attempt_id: args.attemptId,
        p_question_id: args.questionId,
        p_activity_type: args.activityType,
        p_content: args.content,
        p_model: args.model,
        p_prompt_version: args.promptVersion,
      }, { admin: true });
      if (typeof id !== "string" || !/^[0-9a-f-]{36}$/iu.test(id)) throw new BackendError(503, "service_unavailable");
      return id;
    },
    async getActivity(userId: string, activityId: string) {
      const activity = await rpc<StoredActivity | null>("get_ai_learning_activity", {
        p_student_id: userId,
        p_activity_id: activityId,
      }, { admin: true });
      if (!activity || typeof activity !== "object") return null;
      return activity;
    },
    async savePracticeResponse(args) {
      const result = await rpc<{ id: string; is_correct: boolean }>("record_ai_practice_response", {
        p_student_id: args.userId,
        p_activity_id: args.activityId,
        p_item_id: args.itemId,
        p_submitted_answer: args.answer,
      }, { admin: true });
      if (typeof result?.is_correct !== "boolean") throw new BackendError(503, "service_unavailable");
      return result.is_correct;
    },
    logFailure(serviceName, code) {
      console.warn("ai_learning_service_failure", { service: serviceName, code });
    },
    idFactory: () => crypto.randomUUID(),
  };
}
