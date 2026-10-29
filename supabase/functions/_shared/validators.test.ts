import assert from "node:assert/strict";
import test from "node:test";
import {
  OutputValidationError,
  sanitizePracticeItem,
  validateExplanation,
  validatePracticeAnswer,
  validatePracticeOutput,
} from "./validators.ts";

const explanation = {
  concept: "The discriminant predicts the nature of the roots.",
  method_steps: ["Identify a, b, and c.", "Calculate b squared minus four times a times c.", "Use the sign of the result to classify the roots."],
  misconception_response: null,
  worked_example: {
    prompt: "Consider x squared minus five x plus six equals zero.",
    steps: ["Find two factors of six that add to five.", "Write the equation as (x − 2)(x − 3) = 0."],
    answer: "The roots are 2 and 3.",
  },
  comprehension_check: "What does a positive discriminant tell you about the roots?",
};

test("accepts a complete teaching-first explanation schema", () => {
  assert.deepEqual(validateExplanation(explanation), explanation);
});

test("rejects short or extra-field explanations", () => {
  assert.throws(() => validateExplanation({ ...explanation, method_steps: ["Only one step."] }), OutputValidationError);
  assert.throws(() => validateExplanation({ ...explanation, answer: "extra" }), OutputValidationError);
});

test("rejects HTML, links, and code-fenced output", () => {
  assert.throws(() => validateExplanation({ ...explanation, concept: "<script>alert(1)</script>" }), OutputValidationError);
  assert.throws(() => validateExplanation({ ...explanation, comprehension_check: "Visit https://example.com" }), OutputValidationError);
});

test("validates discriminant keys by recomputing the quadratic", () => {
  const items = validatePracticeOutput({
    items: [{
      operation: "discriminant",
      coefficients: { a: 1, b: 5, c: 6 },
      values: ["-1", "0", "1", "3"],
      correct_option: "C",
      explanation: "Substitute into D = b² − 4ac, then evaluate carefully.",
      difficulty: 2,
      objective: "Calculate the discriminant from standard-form coefficients.",
    }],
  }, 1, "Quadratic Equations", () => "00000000-0000-4000-8000-000000000001");
  assert.equal(items[0].verification.expected_value, "1");
  assert.equal(items[0].answer_choices[2].text, "D = 1");
});

test("rejects a wrong answer key even when output is schema-shaped", () => {
  assert.throws(() => validatePracticeOutput({
    items: [{
      operation: "discriminant",
      coefficients: { a: 1, b: 5, c: 6 },
      values: ["-1", "0", "1", "3"],
      correct_option: "A",
      explanation: "Compute b squared minus four times a times c.",
      difficulty: 2,
      objective: "Calculate the discriminant.",
    }],
  }, 1, "Quadratic Equations", () => "00000000-0000-4000-8000-000000000001"), OutputValidationError);
});

test("rejects operation and difficulty drift from the supported target", () => {
  const output = {
    items: [{
      operation: "discriminant",
      coefficients: { a: 1, b: 5, c: 6 },
      values: ["-1", "0", "1", "3"],
      correct_option: "C",
      explanation: "Substitute into D = b² − 4ac, then evaluate.",
      difficulty: 2,
      objective: "Calculate the discriminant.",
    }],
  };
  const idFactory = () => "00000000-0000-4000-8000-000000000001";
  assert.throws(() => validatePracticeOutput(output, 1, "Quadratic Equations", idFactory, "roots", 2), OutputValidationError);
  assert.throws(() => validatePracticeOutput(output, 1, "Quadratic Equations", idFactory, "discriminant", 3), OutputValidationError);
});

test("checks integer roots and rejects irrational or non-integer roots", () => {
  const items = validatePracticeOutput({
    items: [{
      operation: "roots",
      coefficients: { a: 1, b: -5, c: 6 },
      values: ["1, 6", "-2, -3", "2, 3", "-3, -2"],
      correct_option: "C",
      explanation: "Factor the quadratic and set each factor equal to zero.",
      difficulty: 3,
      objective: "Find integer roots using factorisation.",
    }],
  }, 1, "Quadratic Equations", () => "00000000-0000-4000-8000-000000000001");
  assert.equal(items[0].verification.expected_value, "2, 3");
  assert.throws(() => validatePracticeOutput({
    items: [{
      operation: "roots",
      coefficients: { a: 1, b: 0, c: -2 },
      values: ["-2, 2", "-1, 1", "0, 2", "1, 2"],
      correct_option: "A",
      explanation: "Use the quadratic formula.",
      difficulty: 3,
      objective: "Find the roots.",
    }],
  }, 1, "Quadratic Equations", () => "00000000-0000-4000-8000-000000000001"), OutputValidationError);
});

test("practice delivery omits the answer key and explanation until submission", () => {
  const items = validatePracticeOutput({
    items: [{
      operation: "discriminant",
      coefficients: { a: 1, b: 5, c: 6 },
      values: ["-1", "0", "1", "3"],
      correct_option: "C",
      explanation: "Substitute into D = b² − 4ac, then evaluate carefully.",
      difficulty: 2,
      objective: "Calculate the discriminant.",
    }],
  }, 1, "Quadratic Equations", () => "00000000-0000-4000-8000-000000000001");
  const publicItem = sanitizePracticeItem(items[0]);
  assert.equal("correct_answer" in publicItem, false);
  assert.equal("explanation" in publicItem, false);
  assert.equal("verification" in publicItem, false);
  assert.deepEqual(validatePracticeAnswer({ selected_option: "C" }, items[0]), { selected_option: "C" });
  assert.throws(() => validatePracticeAnswer({ selected_option: "C", correct: true }, items[0]), OutputValidationError);
});
