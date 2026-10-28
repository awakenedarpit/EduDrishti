import { describe, expect, it } from "vitest";
import { answerDraftFromSaved, toAnswerPayload } from "./answer";

const ids = ["A", "B", "C"] as const;

describe("toAnswerPayload", () => {
  it("builds a single-choice payload only for a valid option", () => {
    expect(toAnswerPayload("single_choice", "B", ids)).toEqual({ selected_option: "B" });
    expect(toAnswerPayload("single_choice", "Z", ids)).toBeNull();
  });

  it("requires distinct valid multiple-choice options", () => {
    expect(toAnswerPayload("multiple_choice", ["A", "C"], ids)).toEqual({ selected_options: ["A", "C"] });
    expect(toAnswerPayload("multiple_choice", ["A", "A"], ids)).toBeNull();
    expect(toAnswerPayload("multiple_choice", ["Z"], ids)).toBeNull();
    expect(toAnswerPayload("multiple_choice", [], ids)).toBeNull();
  });

  it("converts finite numeric input and rejects blanks or non-finite values", () => {
    expect(toAnswerPayload("numeric", "1.25")).toEqual({ value: 1.25 });
    expect(toAnswerPayload("numeric", "Infinity")).toBeNull();
    expect(toAnswerPayload("numeric", " ")).toBeNull();
  });

  it("trims structured text but never marks it correct", () => {
    expect(toAnswerPayload("short_text", "  x^2 - 5x + 6 = 0  ")).toEqual({ value: "x^2 - 5x + 6 = 0" });
  });

  it("restores saved JSON answer drafts for resumable attempts", () => {
    expect(answerDraftFromSaved("single_choice", { selected_option: "C" })).toBe("C");
    expect(answerDraftFromSaved("multiple_choice", { selected_options: ["A", "D"] })).toEqual(["A", "D"]);
    expect(answerDraftFromSaved("numeric", { value: 2.5 })).toBe("2.5");
  });
});
