export type JsonObject = Record<string, unknown>;

export interface ExplanationOutput {
  concept: string;
  method_steps: string[];
  misconception_response: string | null;
  worked_example: { prompt: string; steps: string[]; answer: string };
  comprehension_check: string;
}

export interface PracticeItem {
  id: string;
  operation: "discriminant" | "roots";
  coefficients: { a: number; b: number; c: number };
  question_text: string;
  question_type: "single_choice";
  answer_choices: Array<{ id: string; text: string }>;
  correct_answer: { selected_option: string };
  explanation: string;
  topic: string;
  difficulty: number;
  intended_learning_objective: string;
  verification: { expected_value: string };
}

export class OutputValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OutputValidationError";
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactKeys(value: JsonObject, expected: string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === expected.length && actual.every((key, index) => key === [...expected].sort()[index]);
}

function safeText(value: unknown, field: string, max: number, min = 1): string {
  if (typeof value !== "string") throw new OutputValidationError(`${field} must be text`);
  const text = value.trim();
  if (text.length < min || text.length > max) throw new OutputValidationError(`${field} has an invalid length`);
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(text)) {
    throw new OutputValidationError(`${field} contains control characters`);
  }
  if (/<\/?[a-z!][^>]*>|javascript:|data:text\/html|```|https?:\/\//iu.test(text)) {
    throw new OutputValidationError(`${field} contains disallowed markup or links`);
  }
  return text;
}

function stringArray(value: unknown, field: string, minItems: number, maxItems: number, itemMax: number): string[] {
  if (!Array.isArray(value) || value.length < minItems || value.length > maxItems) {
    throw new OutputValidationError(`${field} has an invalid item count`);
  }
  return value.map((item, index) => safeText(item, `${field}[${index}]`, itemMax));
}

export function validateExplanation(value: unknown): ExplanationOutput {
  if (!isObject(value) || !exactKeys(value, ["concept", "method_steps", "misconception_response", "worked_example", "comprehension_check"])) {
    throw new OutputValidationError("Explanation shape is invalid");
  }
  const worked = value.worked_example;
  if (!isObject(worked) || !exactKeys(worked, ["prompt", "steps", "answer"])) {
    throw new OutputValidationError("Worked example shape is invalid");
  }
  const misconception = value.misconception_response;
  if (misconception !== null && typeof misconception !== "string") {
    throw new OutputValidationError("Misconception response must be text or null");
  }
  return {
    concept: safeText(value.concept, "concept", 180),
    method_steps: stringArray(value.method_steps, "method_steps", 3, 6, 280),
    misconception_response: misconception === null ? null : safeText(misconception, "misconception_response", 500),
    worked_example: {
      prompt: safeText(worked.prompt, "worked_example.prompt", 220),
      steps: stringArray(worked.steps, "worked_example.steps", 2, 5, 240),
      answer: safeText(worked.answer, "worked_example.answer", 120),
    },
    comprehension_check: safeText(value.comprehension_check, "comprehension_check", 220),
  };
}

function integer(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new OutputValidationError(`${field} must be an integer from ${min} to ${max}`);
  }
  return value;
}

function formatEquation({ a, b, c }: { a: number; b: number; c: number }): string {
  const term = (coefficient: number, suffix: string, first = false): string => {
    if (coefficient === 0) return "";
    const magnitude = Math.abs(coefficient);
    const body = `${magnitude === 1 && suffix ? "" : magnitude}${suffix}`;
    if (first) return coefficient < 0 ? `−${body}` : body;
    return coefficient < 0 ? ` − ${body}` : ` + ${body}`;
  };
  return `${term(a, "x²", true)}${term(b, "x")}${term(c, "", a === 0)} = 0`.trim();
}

export function expectedMathAnswer(
  operation: "discriminant" | "roots",
  coefficients: { a: number; b: number; c: number },
): string {
  const { a, b, c } = coefficients;
  if (a === 0) throw new OutputValidationError("Quadratic coefficient cannot be zero");
  const discriminant = b * b - 4 * a * c;
  if (!Number.isSafeInteger(discriminant)) throw new OutputValidationError("Discriminant is outside the supported range");
  if (operation === "discriminant") return String(discriminant);
  if (discriminant < 0) throw new OutputValidationError("Root practice requires real roots");
  const root = Math.sqrt(discriminant);
  if (!Number.isInteger(root)) throw new OutputValidationError("Root practice requires an integer square discriminant");
  const numerator1 = -b - root;
  const numerator2 = -b + root;
  const denominator = 2 * a;
  if (numerator1 % denominator !== 0 || numerator2 % denominator !== 0) {
    throw new OutputValidationError("Root practice requires integer roots");
  }
  const roots = [numerator1 / denominator, numerator2 / denominator].sort((left, right) => left - right);
  if (roots.some((item) => Math.abs(item) > 40)) throw new OutputValidationError("Roots exceed the supported range");
  return roots.join(", ");
}

function validatePracticeCandidate(
  value: unknown,
  index: number,
  id: string,
  topic: string,
  expectedOperation?: "discriminant" | "roots",
  targetDifficulty?: number,
): PracticeItem {
  const keys = ["operation", "coefficients", "values", "correct_option", "explanation", "difficulty", "objective"];
  if (!isObject(value) || !exactKeys(value, keys)) throw new OutputValidationError(`items[${index}] shape is invalid`);
  if (value.operation !== "discriminant" && value.operation !== "roots") {
    throw new OutputValidationError(`items[${index}].operation is unsupported`);
  }
  if (expectedOperation && value.operation !== expectedOperation) {
    throw new OutputValidationError(`items[${index}].operation does not match the targeted skill`);
  }
  if (!isObject(value.coefficients) || !exactKeys(value.coefficients, ["a", "b", "c"])) {
    throw new OutputValidationError(`items[${index}].coefficients shape is invalid`);
  }
  const coefficients = {
    a: integer(value.coefficients.a, `items[${index}].coefficients.a`, -20, 20),
    b: integer(value.coefficients.b, `items[${index}].coefficients.b`, -20, 20),
    c: integer(value.coefficients.c, `items[${index}].coefficients.c`, -20, 20),
  };
  if (coefficients.a === 0) throw new OutputValidationError("Quadratic coefficient cannot be zero");

  if (!Array.isArray(value.values) || value.values.length !== 4) {
    throw new OutputValidationError(`items[${index}].values must contain four choices`);
  }
  const values = value.values.map((choice, choiceIndex) => {
    if (typeof choice !== "string" || choice.length > 30 || !/^-?\d+(?:, -?\d+)?$/u.test(choice)) {
      throw new OutputValidationError(`items[${index}].values[${choiceIndex}] is invalid`);
    }
    return choice;
  });
  if (new Set(values).size !== 4) throw new OutputValidationError("Practice choices must be distinct");
  const ids = ["A", "B", "C", "D"];
  const correctOption = value.correct_option;
  if (typeof correctOption !== "string" || !ids.includes(correctOption)) {
    throw new OutputValidationError("correct_option must be A, B, C, or D");
  }
  const expected = expectedMathAnswer(value.operation, coefficients);
  if (values.filter((candidate) => candidate === expected).length !== 1 || values[ids.indexOf(correctOption)] !== expected) {
    throw new OutputValidationError("Generated answer key does not match the deterministic math result");
  }

  const difficulty = integer(value.difficulty, `items[${index}].difficulty`, 1, 5);
  if (targetDifficulty !== undefined && difficulty !== targetDifficulty) {
    throw new OutputValidationError(`items[${index}].difficulty does not match the source difficulty`);
  }
  const questionText = value.operation === "discriminant"
    ? `Find the discriminant, D = b² − 4ac, of ${formatEquation(coefficients)}.`
    : `Find the roots of ${formatEquation(coefficients)}.`;
  const answerChoices = values.map((candidate, choiceIndex) => ({
    id: ids[choiceIndex],
    text: value.operation === "discriminant" ? `D = ${candidate}` : `x = ${candidate}`,
  }));
  return {
    id,
    operation: value.operation,
    coefficients,
    question_text: questionText,
    question_type: "single_choice",
    answer_choices: answerChoices,
    correct_answer: { selected_option: correctOption },
    explanation: safeText(value.explanation, `items[${index}].explanation`, 900),
    topic: safeText(topic, "topic", 120),
    difficulty,
    intended_learning_objective: safeText(value.objective, `items[${index}].objective`, 220),
    verification: { expected_value: expected },
  };
}

export function validatePracticeOutput(
  value: unknown,
  expectedCount: number,
  topic: string,
  idFactory: () => string,
  expectedOperation?: "discriminant" | "roots",
  targetDifficulty?: number,
): PracticeItem[] {
  if (!isObject(value) || !exactKeys(value, ["items"]) || !Array.isArray(value.items) || value.items.length !== expectedCount) {
    throw new OutputValidationError("Practice set shape or count is invalid");
  }
  return value.items.map((item, index) => validatePracticeCandidate(
    item,
    index,
    idFactory(),
    topic,
    expectedOperation,
    targetDifficulty,
  ));
}

export function sanitizePracticeItem(item: PracticeItem): Omit<PracticeItem, "operation" | "coefficients" | "correct_answer" | "explanation" | "verification"> {
  return {
    id: item.id,
    question_text: item.question_text,
    question_type: item.question_type,
    answer_choices: item.answer_choices,
    topic: item.topic,
    difficulty: item.difficulty,
    intended_learning_objective: item.intended_learning_objective,
  };
}

export function validatePracticeAnswer(value: unknown, item: PracticeItem): { selected_option: string } {
  if (!isObject(value) || !exactKeys(value, ["selected_option"]) || typeof value.selected_option !== "string") {
    throw new OutputValidationError("Answer must contain only selected_option");
  }
  if (!item.answer_choices.some((choice) => choice.id === value.selected_option)) {
    throw new OutputValidationError("Selected option is not part of this practice item");
  }
  return { selected_option: value.selected_option };
}

export function isPracticeItem(value: unknown): value is PracticeItem {
  if (!isObject(value) || typeof value.id !== "string" || !Array.isArray(value.answer_choices)) return false;
  return typeof value.question_text === "string"
    && typeof value.explanation === "string"
    && isObject(value.correct_answer)
    && value.correct_answer.selected_option !== undefined
    && value.question_type === "single_choice";
}
