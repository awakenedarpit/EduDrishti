# Frontend integration contract (Stage 7)

This contract prepares the existing Supabase backend for a separately generated Google Stitch frontend. Stitch source has not been supplied, so this document intentionally does not assume a UI framework, file layout, route model, or component props. The canonical machine-readable contract is [OpenAPI 3.1](api/openapi.yaml); shared TypeScript transport/domain types are in `web/src/lib/api-contracts.ts`.

## Current availability and audit findings

The application API is Supabase Auth plus the PostgREST database API. Public SQL functions are called as `POST /rest/v1/rpc/{function}`. Stage 1–3 and Stage 6 migrations in the current main source define authenticated RPCs; public application tables have RLS. Stage 6 entry points check teacher role and class ownership server-side. User-scoped endpoints derive the caller from `auth.uid()` or the validated user JWT; do not pass a user ID as authority.

The connected project was inspected on 2026-11-01. Its migration ledger records Stages 1–4, but not Stage 5 or Stage 6. There are also migration-version mismatches to reconcile: the remote Stage 3 ledger version is `20261028101421` while the current main source file is `20261028093000_stage3_misconception_engine.sql`; remote Stage 4 is recorded as `20261030194703` while its integration-branch filename is `20261029222500_stage4_ai_learning_services.sql`. Stage 5's source migration exists on the `stage5-learning-progress` branch and is not installed (`progress_records.calculation_version` is absent). Stage 6's eight teacher RPCs exist remotely with the expected signatures and `SECURITY DEFINER`, empty `search_path`, authenticated-only execute grants; their migration-ledger entry is missing. Treat this as schema/ledger drift and do not use the ledger alone as proof that a function is absent or present. No Stage 6 migration re-apply or fake migration repair was attempted.

The Stage 3 source contract and live schema differ: source/UI types include `get_my_recent_diagnoses` and some docs refer to `get_my_diagnoses`, while the inspected database exposes `get_student_diagnoses(p_attempt_id uuid)` and does not expose the other two names. The current frontend source calls the recent-diagnoses RPC. Do not build against that route until a migration or compatibility alias is installed and verified. The published OpenAPI includes the live `get_student_diagnoses` name and marks the source-only route as unavailable below.

Stage 4 defines three JWT-verified Edge Functions on the Stage 5 integration branch, but the connected project currently lists **no deployed Edge Functions**. Its routes are documented in OpenAPI as source-defined, not live. Stage 5 learning-progress RPCs are also source-only and intentionally omitted from the live endpoint list. A client should render an unavailable/capability state for these features until deployment and smoke checks succeed.

### Migration repair outcome and remaining blocker

The Stage 4 migration file had invalid exception quoting/input checks. The corrected SQL was validated by 44 Stage 4/5 branch tests and `git diff --check`, committed as `c5b4f06` (`fix: repair Stage 4 migration SQL syntax`), and pushed to `stage5-learning-progress`. Stage 4 is recorded remotely as migration `20261030194703`. Stage 5 could not be applied from this desktop: no Supabase CLI, `psql`, CLI access token, or file-backed migration tool is available. The remote database migration connector accepts SQL text only; no partial or reconstructed Stage 5 SQL was submitted. The Stage 5 migration must be applied through an authenticated, reviewed Supabase CLI workflow before integrating progress features.

A live database security advisory also reports RLS disabled on four `private` tables: `private.misconception_rules`, `private.ai_request_buckets`, `private.ai_learning_activities`, and `private.ai_practice_responses`. The schema is not in the exposed API schema list and the service layer uses service-only paths, but verify grants and definer access in an authorized security review. Do not enable RLS without designing/validating the needed owner/service policies; this contract does not apply a remediation.

## Authentication and ownership

1. Initialize the Supabase browser client with the project URL and publishable/legacy anon key only. Send the publishable key in `apikey` and the signed-in user's access token as `Authorization: Bearer <access_token>`; the key identifies the project, the JWT identifies the user.
2. Let `supabase-js` persist, refresh, and restore the session. Subscribe to `onAuthStateChange`; call `getSession()` for initial restoration. Wait for the profile/role load before showing role-specific navigation. A missing profile is a provisioning/loading error, not a student default supplied by the frontend.
3. Sign-out clears the local UI session. Never store an access token in application-managed local storage or put it in a URL, log, analytics event, or screenshot. Do not copy session tokens between accounts.
4. Database functions and RLS are the authorization boundary. Never use frontend filtering to protect class, attempt, student, assessment, or response data. A foreign row may be denied (`42501`) or invisible (empty list/404) by design. Do not infer existence from errors.
5. New Auth users receive the `student` role. Teacher provisioning is trusted-operator-only. `create_class` derives ownership from the authenticated teacher; `enroll_student` checks teacher ownership and student role.
6. Stage 2 student assessment functions require an authenticated student and validate assessment availability/enrollment, attempt ownership, question membership, and answer shape. Answer keys and feedback are withheld until the signed-in student's graded result.
7. Stage 3 diagnosis reads are student-own-attempt or teacher-own-class scoped. Empty/unmatched diagnosis data is inconclusive, not a positive or negative learner trait.
8. Stage 6 teacher RPCs require an authenticated teacher who owns the class; assessment IDs must belong to that class, and student detail additionally requires enrollment in that class. Report data excludes student identifiers and submitted answers.
9. Stage 4 Edge Functions additionally validate the JWT with Auth and check `profiles.app_role = student`. Stage 4 internal writes/context/rate-limit calls use a server-only secret credential. The service-role/secret key is never a browser credential.

## Stable request and response conventions

- RPC: JSON object with exact `p_...` argument names; no user-supplied ownership claims, scores, diagnosis results, or privileged IDs beyond identifiers that the function re-authorizes. JSON results retain existing snake_case keys and `schema_version` fields. `get_assessment`, results, diagnosis, and teacher analytics use their existing response envelopes.
- Edge Functions: `POST` JSON, bearer session required, reject unknown body fields, max body 8 KiB. Return the endpoint-specific success shape. Errors retain the current `{ "error": { "code", "message" } }` envelope; AI fallback responses may include `fallback` and `source` alongside `error`.
- PostgREST errors: standard `{ "code", "message", "details", "hint" }`. Preserve the SQLSTATE code for program logic; do not render raw details/hints. The client-side `normalizeApiError` maps both wire forms to `ApiError` categories without changing raw API responses.
- There is no global database RPC rate limit in the current source. Stage 4 AI functions have per-student database-backed limits: 6 explanation, 3 practice-generation, and 15 answer-check requests per minute. Honor HTTP 429 and any `Retry-After` header if one is added; the current Edge handler does not promise that header.
- Not found vs authorization: Edge Functions use 404 for missing activity/item/question; teacher/student scope checks generally use 42501 to avoid cross-class disclosure. Direct RLS reads can return an empty array. A `22023` SQLSTATE can mean invalid input or a missing item depending on the function; classify it as validation unless endpoint context proves otherwise.

### Error mapping for client presentation

| Canonical category | Typical source | UI behavior |
|---|---|---|
| `unauthenticated` | HTTP 401, SQLSTATE `28000`, `PGRST301` | Refresh session or send to sign-in; preserve a safe retry path. |
| `forbidden` | HTTP 403, SQLSTATE `42501`, `not_authorized` | Show access unavailable; do not reveal whether a foreign row exists. |
| `not_found` | HTTP 404, `P0002`, `02000`, `PGRST116`, explicit `*_not_found` | Show an unavailable/removed state with navigation back. |
| `validation_failed` | HTTP 400/413/415/422, `22023`, `23514` | Keep the form values; show field/action-level corrective copy. |
| `conflict` | HTTP 409, `55000`, `23505` | Refresh current attempt/activity state; do not blindly retry mutations. |
| `rate_limited` | HTTP 429, `rate_limited` | Explain cooldown; retry only after the window. |
| `capability_unavailable` | `PGRST202`, `PGRST204`, `42883` | Mark the feature as not deployed/configured; don't offer repeated retry loops. |
| `service_unavailable` / `server_error` | HTTP 5xx, network failure, AI fallback/unavailable | Preserve entered work, offer bounded retry; show existing guidance fallback when provided. |

The normalized type's `message` is safe UI copy. Keep the original code for diagnostics, but do not expose DB detail/hint, secrets, provider bodies, answer keys, or raw student answers in logs/toasts.

## Loading, empty, success and error states

Use a discriminated state (`RequestState<T>` in `api-contracts.ts`) rather than interpreting `null`, `[]`, or errors as interchangeable:

- **Loading:** show a stable skeleton/inline progress indicator. Keep navigation and previously loaded safe data available. Do not flash a permission-specific view before session/profile resolution.
- **Empty:** show an endpoint-appropriate empty state (`no_records`, `no_assessments`, `no_scored_evidence`, or `insufficient_evidence`). A class with no learners/graded work is valid; zero denominator metrics may be `null`, not zero. Empty diagnosis/heatmap cells do not prove no learning difficulty.
- **Success:** render only the data returned for the authorized scope. Label demo/synthetic data if `is_demo` is true. Keep `schema_version` available for version-aware adaptation.
- **Error:** render normalized category and a safe action. `forbidden` is not empty; `not_found`/RLS-hidden items are not proof of foreign ownership. Capability-unavailable features should be disabled or marked not deployed.

Example states (synthetic only):

```ts
const loading: RequestState<AssessmentSummary[]> = { status: "loading" };
const empty: RequestState<AssessmentSummary[]> = {
  status: "empty", data: [], reason: "no_assessments",
};
const success: RequestState<AssessmentSummary[]> = {
  status: "success", data: [{
    assessment_id: "00000000-0000-4000-8000-000000000101",
    title: "Quadratic Equations — Sample",
    description: "Synthetic example only", assessment_type: "diagnostic",
    class_id: null, is_template: true, question_count: 7, total_points: 7,
    opens_at: null, closes_at: null,
  }],
};
const failed: RequestState<AssessmentSummary[]> = {
  status: "error", error: {
    category: "unauthenticated", code: "28000",
    message: "Your session has expired. Sign in again to continue.",
    httpStatus: 401, retryable: false,
  },
};
```

## Environment and safe configuration

| Variable | Where | Purpose / safe handling |
|---|---|---|
| `VITE_SUPABASE_URL` | `web/.env.local`, Vercel browser build | Supabase project URL; public configuration. |
| `VITE_SUPABASE_ANON_KEY` | `web/.env.local`, Vercel browser build | Publishable/legacy anon key; intended for clients, safe only with RLS/RPC auth. |
| `SUPABASE_PROJECT_REF` | ignored root `.env`/operator shell | Non-secret project reference for CLI target confirmation. |
| `SUPABASE_ACCESS_TOKEN` | developer's local secret store/shell only | Supabase CLI deployment credential; never browser-visible, committed, or logged. |
| `SUPABASE_URL` | Edge Function runtime | Supabase URL injected by platform; server use only. |
| `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_ANON_KEY` | Edge Function runtime | Server uses publishable key with the caller's JWT for user-scoped Auth/PostgREST requests. Prefer current platform-injected variable. |
| `SUPABASE_SECRET_KEYS` / `SUPABASE_SECRET_KEY` / legacy `SUPABASE_SERVICE_ROLE_KEY` | Edge Function runtime | Privileged server-only credential for internal service RPCs; never `VITE_`-prefixed or sent to a browser. |
| `GEMINI_API_KEY` | Edge Function secret manager only | Provider credential; sent only server-to-server in a header. |
| `GEMINI_MODEL` | Edge Function secret/config | Optional allow-listed model name; source default is `gemini-3.8-flash`. |
| `AI_ALLOWED_ORIGINS` | Edge Function secret/config | Comma-separated exact browser origins; set production origin(s), not wildcard. |

Copy placeholders from `.env.example`, `web/.env.example`, and `supabase/functions/.env.example`; store real server keys in the Supabase/Vercel secret manager with least privilege. Check built bundles, source maps, logs, and deployment previews for accidental credential leakage. Browser code may contain only URL + publishable key.

## Examples

All identifiers and content below are synthetic. Use the signed-in user's current access token and publishable key.

List available assessments:

```http
POST /rest/v1/rpc/list_available_assessments
apikey: <publishable-key>
Authorization: Bearer <student-access-token>
Content-Type: application/json

{}
```

Synthetic response:

```json
[
  {
    "assessment_id": "00000000-0000-4000-8000-000000000101",
    "title": "Quadratic Equations — Sample",
    "assessment_type": "diagnostic",
    "class_id": null,
    "is_template": true,
    "question_count": 7,
    "total_points": 7,
    "opens_at": null,
    "closes_at": null
  }
]
```

Get a teacher's authorized classes:

```http
POST /rest/v1/rpc/list_teacher_classes
apikey: <publishable-key>
Authorization: Bearer <teacher-access-token>
Content-Type: application/json

{}
```

Synthetic response:

```json
[{"id":"00000000-0000-4000-8000-000000000201","name":"Class 10A (Synthetic)","grade_level":10,"subject":"Mathematics","active_enrollment_count":0,"assessment_count":0}]
```

Representative validation failure from PostgREST (the actual `details`/`hint` text is database-generated and should not be shown):

```json
{"code":"22023","message":"Answer must be a JSON object no larger than 16 KiB","details":null,"hint":null}
```

Representative Edge Function error (source-defined, not deployed in the inspected project):

```json
{"error":{"code":"rate_limited","message":"The request limit has been reached. Try again later."}}
```

## Compatibility and change policy

- Keep all existing RPC names, `p_...` parameter names, snake_case response keys, `schema_version`, and result/error envelopes. New properties can be additive; do not rename keys or replace raw server errors without a versioned contract.
- `submit_assessment(p_attempt_id)` is a legacy compatibility alias; new clients use `complete_assessment`.
- Existing frontend code reads `classes`, `assessment_attempts`, and `responses` directly under RLS and invokes RPCs. Do not bypass RLS or require a server key in the Stitch client. The Stage 6 `list_teacher_classes()` is additive and returns aggregate counts.
- Do not integrate Stage 5 learning-progress functions or Stage 4 Edge Functions as live until migration/function deployment and authenticated smoke tests are complete.
- `get_student_diagnoses` is the currently inspected remote route. Source-only `get_my_recent_diagnoses`/`get_my_diagnoses` names are not interchangeable; reconcile by a forward-compatible migration/alias before clients depend on them.
- All future breaking API changes require an explicit versioned migration and a compatibility window. The new Stitch code should be adapted after it is supplied; this document is not a claim about its component contract.
