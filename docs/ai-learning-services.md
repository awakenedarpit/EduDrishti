# Stage 4: Secure AI learning services

Stage 4 adds server-side Gemini services for personalized explanations and targeted Class 10 Quadratic Equations practice. The Edge Functions are user-authenticated and accept only an attempt UUID and question UUID. They load the signed-in student's own graded assessment result through the existing `get_student_results` RPC. Stage 3 findings are loaded through `get_student_diagnoses`; if that RPC is not installed, the services continue without claiming a diagnosis. They never accept client-authored answers, topic labels, or diagnosis claims.

## Endpoints

All endpoints are `POST /functions/v1/<function-name>` and require a signed-in student session in the `Authorization: Bearer <Supabase access token>` header. Supabase JWT verification remains enabled in `supabase/config.toml`; the handler also validates the access token with Supabase Auth and checks `profiles.app_role = 'student'`. Requests must be JSON and are capped at 8 KiB.

### `personalized-explanation`

Request:

```json
{
  "attempt_id": "<graded-attempt-uuid>",
  "question_id": "<question-uuid>"
}
```

The question must be an answered item in the student's own graded attempt. The response contains `source: "ai_generated"`, the persisted `activity_id`, `model`, `prompt_version`, and an explanation with `concept`, `method_steps`, optional supported `misconception_response`, a worked example, and a final `comprehension_check`. The prompt requires instruction rather than an answer-only reply. The service returns a saved assessment-guidance fallback and any matching rule-based evidence if Gemini is unavailable.

### `targeted-practice`

Request:

```json
{
  "attempt_id": "<graded-attempt-uuid>",
  "question_id": "<question-uuid>",
  "count": 2
}
```

`count` is optional and restricted to 1–3. Practice is offered for a wrong answer or a supported diagnosis. If no rule-based diagnosis matches the item, the service targets the tested skill and does not guess why the learner was wrong. In this first release, practice is supported only for Class 10 Mathematics quadratic questions tagged `discriminant_*` or `factorisation_roots`; other objectives return `409 unsupported_practice_target` without calling Gemini. Discriminant questions generate discriminant items, and factorisation/root questions generate integer-root items. Generated difficulty must equal the source question’s stored difficulty. The JSON Schema-constrained model output is independently validated; the server recomputes the discriminant or roots and rejects an incorrect key, wrong operation or difficulty, invalid coefficients, non-integer roots, malformed choices, or unexpected fields.

The response intentionally omits the answer key and explanation. It includes `activity_id`, question text, choices, topic, difficulty, learning objective, and an instruction to submit an answer to `check-practice-answer`. This prevents the generated key from being exposed before the learner attempts the item.

### `check-practice-answer`

Request:

```json
{
  "activity_id": "<practice-activity-uuid>",
  "item_id": "<generated-item-uuid>",
  "answer": { "selected_option": "B" }
}
```

The function looks up the activity using both the activity ID and authenticated student ID. It validates the submitted option, asks the database to verify it against the private stored key, records the attempt, and then returns whether it is correct, the explanation, and the correct option. Answer keys are stored in the non-exposed `private.ai_learning_activities` table, not in the browser-facing response or a public table.

## Validation, privacy, and reliability

Gemini requests use a server-side `GEMINI_API_KEY` header and a configurable `GEMINI_MODEL` (default `gemini-3.8-flash`). The key is never sent to the browser, placed in a URL, or included in logs. Prompts exclude user IDs, emails, names, and assessment history. Multiple-choice and numeric answers are reduced to a short summary. Free-text answers are omitted from Gemini prompts to avoid sending arbitrary personal text. Diagnosis context is included only when Stage 3 returned an exact `rule_based` match for the requested question. It is described as a supported pattern, not proof of the student's reasoning.

Generation has a 12-second provider timeout, a five-second Supabase Auth/PostgREST timeout, fixed token ceilings, capped provider/database response bodies, no retry loop, a strict output schema, and output validation for size, structure, text safety, and math consistency. Database-backed per-minute limits are 6 explanation calls, 3 practice-generation calls, and 15 answer checks per student. Provider refusals, empty output, malformed JSON, timeouts, rate limits, and provider errors produce bounded error responses without provider body details. The deterministic Stage 3 diagnosis remains available as the fallback; no AI diagnosis is generated.

Generated activity records contain the student/attempt/question references, activity type, source (`ai_generated`), provider, model, prompt version, and validated content. Practice response history is stored separately. These records live in the non-exposed `private` schema. Server-only RPCs validate student ownership and graded-attempt membership before writing or retrieving data.

## Secrets and local run

Supabase injects its project URL and API keys into hosted Edge Functions. The server uses the caller's access token for student-scoped assessment RPCs and the Supabase secret/service-role key only for server-side context lookup, rate limiting, and private artifact RPCs. Configure `GEMINI_API_KEY`, optionally `GEMINI_MODEL`, and `AI_ALLOWED_ORIGINS` through the Supabase Edge Function secrets configuration. Never put these values in `web/.env`, frontend source, source maps, or a committed env file.

For local development, copy `supabase/functions/.env.example` to the ignored `supabase/functions/.env`, add a development Gemini key, apply migrations to a local Supabase stack, then run:

```sh
supabase start
supabase db reset
supabase functions serve personalized-explanation targeted-practice check-practice-answer --env-file supabase/functions/.env
```

The migration is additive source code; it has not been applied to the remote project. Before any remote migration or function deployment, inspect the exact Supabase project, migration ledger, and secrets configuration. No Gemini credential was available for this implementation, so a live-provider request remains unverified.

## Tests

Run deterministic validation and mocked-handler tests with:

```sh
node --experimental-strip-types --test supabase/functions/_shared/*.test.ts
python3 -m unittest discover -s tests -v
```

The pgTAP permission checks are in `supabase/tests/ai_learning_services.test.sql` and run with `supabase test db` against a local Supabase database. They do not substitute for a hosted migration review or live Gemini test.

## References

- [Gemini API structured output](https://ai.google.dev/gemini-api/docs/generate-content/structured-output)
- [Gemini API generateContent reference](https://ai.google.dev/api/generate-content)
- [Gemini 3.8 Flash model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
- [Supabase API keys and roles](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase Edge Function authentication](https://supabase.com/docs/guides/functions/auth)
- [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets)
- [PostgreSQL JSON processing functions](https://www.postgresql.org/docs/current/functions-json.html)
