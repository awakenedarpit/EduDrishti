import type { Json } from "../../lib/database.types";
import type { QuestionType } from "./api";

export type AnswerDraft = string | string[];

export function toAnswerPayload(
  type: QuestionType,
  draft: AnswerDraft,
  validOptionIds: readonly string[] = [],
): Json | null {
  if (type === "single_choice") {
    if (typeof draft !== "string" || !validOptionIds.includes(draft)) return null;
    return { selected_option: draft };
  }

  if (type === "multiple_choice") {
    if (!Array.isArray(draft) || draft.length === 0) return null;
    const unique = [...new Set(draft)];
    if (unique.length !== draft.length || unique.some((id) => !validOptionIds.includes(id))) return null;
    return { selected_options: unique };
  }

  if (typeof draft !== "string" || !draft.trim()) return null;
  if (type === "numeric") {
    const value = Number(draft);
    return Number.isFinite(value) ? { value } : null;
  }

  return { value: draft.trim() };
}

export function answerDraftFromSaved(type: QuestionType, answer: Json): AnswerDraft {
  if (!answer || typeof answer !== "object" || Array.isArray(answer)) return type === "multiple_choice" ? [] : "";
  const record = answer as Record<string, Json | undefined>;
  if (type === "single_choice") return typeof record.selected_option === "string" ? record.selected_option : "";
  if (type === "multiple_choice") {
    return Array.isArray(record.selected_options)
      ? record.selected_options.filter((value): value is string => typeof value === "string")
      : [];
  }
  return typeof record.value === "number" || typeof record.value === "string" ? String(record.value) : "";
}
