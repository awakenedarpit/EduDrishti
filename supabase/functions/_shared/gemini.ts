export class GeminiServiceError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status = 503) {
    super(code);
    this.name = "GeminiServiceError";
    this.code = code;
    this.status = status;
  }
}

export interface GeminiPrompt {
  systemInstruction: string;
  userPrompt: string;
  responseSchema: unknown;
}

export interface GeminiConfig {
  apiKey: string;
  model: string;
  fetcher?: typeof fetch;
  timeoutMs?: number;
}

function extractText(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const record = body as Record<string, unknown>;
  const candidates = record.candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const candidate = candidates[0];
  if (typeof candidate !== "object" || candidate === null) return null;
  const item = candidate as Record<string, unknown>;
  const reason = item.finishReason;
  if (typeof reason === "string" && reason !== "STOP" && reason !== "FINISH_REASON_UNSPECIFIED") {
    throw new GeminiServiceError(reason === "SAFETY" || reason === "PROHIBITED_CONTENT" ? "provider_refused" : "provider_incomplete", 502);
  }
  const content = item.content;
  if (typeof content !== "object" || content === null) return null;
  const parts = (content as Record<string, unknown>).parts;
  if (!Array.isArray(parts)) return null;
  const texts = parts.flatMap((part) => {
    if (typeof part !== "object" || part === null) return [];
    const text = (part as Record<string, unknown>).text;
    return typeof text === "string" ? [text] : [];
  });
  return texts.length ? texts.join("\n").trim() : null;
}

async function readBoundedJson(response: Response): Promise<unknown> {
  const maxBytes = 65_536;
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new GeminiServiceError("provider_response_too_large", 502);
  }
  if (!response.body) throw new GeminiServiceError("provider_malformed_response", 502);
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new GeminiServiceError("provider_response_too_large", 502);
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
    throw new GeminiServiceError("provider_malformed_response", 502);
  }
}

export async function generateGeminiJson(
  config: GeminiConfig,
  prompt: GeminiPrompt,
  maxOutputTokens: number,
): Promise<unknown> {
  if (!config.apiKey) throw new GeminiServiceError("provider_not_configured", 503);
  if (!/^[a-zA-Z0-9._-]{1,80}$/u.test(config.model)) throw new GeminiServiceError("provider_configuration_invalid", 503);
  const fetcher = config.fetcher ?? fetch;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs ?? 12_000);
  try {
    const response = await fetcher(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.model)}:generateContent`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": config.apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: prompt.systemInstruction }] },
          contents: [{ role: "user", parts: [{ text: prompt.userPrompt }] }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: prompt.responseSchema,
            temperature: 0.2,
            topP: 0.8,
            maxOutputTokens,
          },
          safetySettings: [
            { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
            { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
            { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
            { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
          ],
        }),
        signal: controller.signal,
      },
    );

    if (!response.ok) {
      if (response.status === 429) throw new GeminiServiceError("provider_rate_limited", 503);
      if (response.status >= 500) throw new GeminiServiceError("provider_unavailable", 503);
      throw new GeminiServiceError("provider_request_rejected", 502);
    }

    const body = await readBoundedJson(response);
    const text = extractText(body);
    if (!text) throw new GeminiServiceError("provider_empty_response", 502);
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new GeminiServiceError("provider_invalid_json", 502);
    }
  } catch (error) {
    if (error instanceof GeminiServiceError) throw error;
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new GeminiServiceError("provider_timeout", 503);
    }
    throw new GeminiServiceError("provider_unavailable", 503);
  } finally {
    clearTimeout(timeout);
  }
}
