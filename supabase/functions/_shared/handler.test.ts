import assert from "node:assert/strict";
import test from "node:test";
import { GeminiServiceError } from "./gemini.ts";
import { createAIHandler, type ServiceDependencies } from "./handler.ts";
import { validatePracticeOutput } from "./validators.ts";

const attemptId = "11111111-1111-4111-8111-111111111111";
const questionId = "22222222-2222-4222-8222-222222222222";
const activityId = "33333333-3333-4333-8333-333333333333";
const itemId = "44444444-4444-4444-8444-444444444444";
const userId = "55555555-5555-4555-8555-555555555555";

const generatedExplanation = {
  concept: "Use the discriminant to classify the roots of a quadratic equation.",
  method_steps: ["Write the equation in standard form.", "Identify a, b, and c.", "Calculate b squared minus four times a times c."],
  misconception_response: null,
  worked_example: {
    prompt: "Classify x squared plus five x plus six equals zero.",
    steps: ["Calculate 25 minus 24.", "The discriminant is positive."],
    answer: "The equation has two distinct real roots.",
  },
  comprehension_check: "What does a positive discriminant tell you about the roots?",
};

const practiceModelOutput = {
  items: [{
    operation: "discriminant",
    coefficients: { a: 1, b: 5, c: 6 },
    values: ["-1", "0", "1", "3"],
    correct_option: "C",
    explanation: "Substitute into D = b² − 4ac, then simplify.",
    difficulty: 2,
    objective: "Calculate a quadratic discriminant.",
  }],
};

function makeDependencies(overrides: Partial<ServiceDependencies> = {}): ServiceDependencies {
  return {
    allowedOrigins: ["https://learn.example"],
    model: "gemini-test-model",
    authenticate: async () => ({ userId, accessToken: "test-user-access-token-1234567890" }),
    consumeRateLimit: async () => true,
    getAssessmentResult: async () => ({
      attempt: { id: attemptId, assessment_id: "66666666-6666-4666-8666-666666666666", status: "graded" },
      items: [{
        question_id: questionId,
        question_type: "short_text",
        prompt: "Find the discriminant of x² + 5x + 6 = 0.",
        answer: { text_response: "this is learner private text that must not be sent" },
        is_answered: true,
        is_correct: false,
        correct_answer: { value: "1" },
        explanation: "Use D = b² − 4ac.",
      }],
    }),
    getDiagnoses: async () => [],
    getQuestionMetadata: async () => ({
      topic: { title: "Quadratic Equations", subject: "Mathematics", grade_level: 10, code: "quadratic-equations" },
      concept: "discriminant_calculation",
      difficulty: 2,
    }),
    generate: async () => generatedExplanation,
    saveActivity: async () => activityId,
    getActivity: async () => null,
    savePracticeResponse: async () => true,
    idFactory: () => itemId,
    ...overrides,
  };
}

function post(url: string, body: unknown, origin = "https://learn.example"): Request {
  return new Request(url, {
    method: "POST",
    headers: {
      authorization: "Bearer test-user-access-token-1234567890",
      "content-type": "application/json",
      origin,
    },
    body: JSON.stringify(body),
  });
}

test("personalized explanation uses server-loaded context and omits raw short-text answers", async () => {
  let promptText = "";
  let saved = false;
  const handler = createAIHandler("explanation", makeDependencies({
    generate: async (prompt) => {
      promptText = prompt.userPrompt;
      return generatedExplanation;
    },
    saveActivity: async () => {
      saved = true;
      return activityId;
    },
  }));
  const response = await handler(post("https://edge.example/personalized-explanation", { attempt_id: attemptId, question_id: questionId }));
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.source, "ai_generated");
  assert.equal(body.activity_id, activityId);
  assert.equal(saved, true);
  assert.equal(promptText.includes("this is learner private text"), false);
  assert.match(promptText, /short-text response was recorded but is omitted/u);
});

test("targeted practice persists validated keys but withholds them from the generation response", async () => {
  let stored: unknown = null;
  const handler = createAIHandler("practice", makeDependencies({
    generate: async () => practiceModelOutput,
    saveActivity: async (args) => {
      stored = args.content;
      return activityId;
    },
  }));
  const response = await handler(post("https://edge.example/targeted-practice", {
    attempt_id: attemptId,
    question_id: questionId,
    count: 1,
  }));
  const text = await response.text();
  const body = JSON.parse(text) as Record<string, unknown>;
  assert.equal(response.status, 200);
  assert.equal(body.source, "ai_generated");
  assert.equal((body.items as Array<Record<string, unknown>>)[0].id, itemId);
  assert.equal(text.includes("correct_answer"), false);
  assert.equal(text.includes("Substitute into D"), false);
  assert.equal(JSON.stringify(stored).includes("correct_answer"), true);
});

test("practice answer is scoped to the authenticated learner and returns DB-verified result", async () => {
  const generated = validatePracticeOutput(practiceModelOutput, 1, "Quadratic Equations", () => itemId);
  let lookedUpUser = "";
  let savedAnswer = "";
  const handler = createAIHandler("practice_answer", makeDependencies({
    getActivity: async (requestedUser, requestedActivity) => {
      lookedUpUser = requestedUser;
      assert.equal(requestedActivity, activityId);
      return { id: activityId, activity_type: "practice", content: { items: generated }, model: "test", prompt_version: "test" };
    },
    savePracticeResponse: async (args) => {
      savedAnswer = args.answer.selected_option;
      return true;
    },
  }));
  const response = await handler(post("https://edge.example/check-practice-answer", {
    activity_id: activityId,
    item_id: itemId,
    answer: { selected_option: "C" },
  }));
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(lookedUpUser, userId);
  assert.equal(savedAnswer, "C");
  assert.equal(body.is_correct, true);
  assert.deepEqual(body.correct_answer, { selected_option: "C" });
});

test("unsupported learning objectives never invoke practice generation", async () => {
  let generated = false;
  const handler = createAIHandler("practice", makeDependencies({
    getQuestionMetadata: async () => ({
      topic: { title: "Quadratic Equations", subject: "Mathematics", grade_level: 10, code: "quadratic-equations" },
      concept: "situational_modelling",
      difficulty: 2,
    }),
    generate: async () => { generated = true; return practiceModelOutput; },
  }));
  const response = await handler(post("https://edge.example/targeted-practice", { attempt_id: attemptId, question_id: questionId }));
  const body = await response.json();
  assert.equal(response.status, 409);
  assert.equal(body.error.code, "unsupported_practice_target");
  assert.equal(generated, false);
});

test("provider failure returns existing assessment guidance without claiming AI output", async () => {
  const handler = createAIHandler("explanation", makeDependencies({
    generate: async () => { throw new GeminiServiceError("provider_timeout", 503); },
  }));
  const response = await handler(post("https://edge.example/personalized-explanation", { attempt_id: attemptId, question_id: questionId }));
  const body = await response.json();
  assert.equal(response.status, 503);
  assert.equal(body.source, "existing_assessment_guidance");
  assert.equal(body.fallback.original_explanation, "Use D = b² − 4ac.");
  assert.equal(JSON.stringify(body).includes("provider_timeout"), false);
});

test("rate limits and disallowed origins stop work before AI generation", async () => {
  let generated = false;
  const limited = createAIHandler("explanation", makeDependencies({
    consumeRateLimit: async () => false,
    generate: async () => { generated = true; return generatedExplanation; },
  }));
  const rateResponse = await limited(post("https://edge.example/personalized-explanation", { attempt_id: attemptId, question_id: questionId }));
  assert.equal(rateResponse.status, 429);
  assert.equal(generated, false);

  const blocked = createAIHandler("explanation", makeDependencies());
  const originResponse = await blocked(post("https://edge.example/personalized-explanation", { attempt_id: attemptId, question_id: questionId }, "https://attacker.example"));
  assert.equal(originResponse.status, 403);
});
