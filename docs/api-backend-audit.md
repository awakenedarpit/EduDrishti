# Backend audit and integration readiness (Stage 7)

Audit snapshot: 2026-11-01. This document distinguishes repository source, connected-database metadata, and deployment verification; one must not be inferred from another.

## Service and migration inventory

| Area | Implemented source | Authorization and access | Readiness |
|---|---|---|---|
| Stage 1 identity/classes/RLS | Profiles, classes, enrollments, question bank, assessments, attempts, responses, learning/progress tables; `create_class`, `enroll_student`, attempt start/save/submit RPCs. | New Auth users become students; teacher provisioning is trusted only. Owner-based class policy and student-owned attempts/responses. RPCs require authenticated; public access revoked. | Remote Stage 1 ledger entry exists; public application tables inspected with RLS enabled. |
| Stage 2 assessment | Listing/retrieval, start, save, complete, results; protected answer keys and guidance. | Authenticated students; server checks role, template/enrollment, attempt and question scope. Keys/feedback visible only after own graded result. `submit_assessment` is retained alias. | Remote Stage 2 ledger entry exists; frontend uses the documented functions. |
| Stage 3 diagnosis | Reviewed answer-pattern trigger and candidate evidence; student diagnosis and teacher class aggregates. | Student-own attempt and teacher-owned class; records read-only to clients. Confidence is heuristic; unmatched errors remain inconclusive. | Remote exposes `get_student_diagnoses(p_attempt_id)`; source/UI also names `get_my_recent_diagnoses` and older docs `get_my_diagnoses`, neither was present in the inspected remote function inventory. Reconcile before using those names. |
| Stage 4 AI learning services | Edge routes `personalized-explanation`, `targeted-practice`, `check-practice-answer`; server-only RPCs `consume_ai_request`, `get_ai_learning_context`, `get_ai_learning_activity`, `store_ai_learning_activity`, `record_ai_practice_response`; private artifact/answer storage, rate limits, output validation. | JWT + authenticated student profile; server-only secret for internal calls, caller JWT for own graded assessment context. Rate limits are 6/3/15 calls per minute per student. | Corrected migration source is committed/pushed on `stage5-learning-progress`; remote ledger records Stage 4. Connected project lists no deployed Edge Functions. Live Gemini path is unverified. |
| Stage 5 learning progress | Dated/versioned mastery snapshots; `get_student_progress_overview`, `get_student_topic_mastery`, `get_student_assessment_history`, `get_student_recent_learning_activity`, `get_student_mastery_history`, `get_student_progress_comparison`, `get_class_learning_progress`. | Student identity derives from session; teacher aggregate is class scoped; internal aggregators/service writes are not browser-callable. | Migration source exists on integration branch but remote migration ledger/schema omit Stage 5. Do not expose its functions to clients yet. |
| Stage 6 teacher dashboard | Eight class/assessment analytics, heatmap, support, student detail, recommendations and aggregate report RPCs. | Public entry points are `SECURITY DEFINER`, fixed empty `search_path`, authenticated-only execute; class ownership and enrollment are rechecked server-side. | Eight functions are installed remotely with expected signatures, but no Stage 6 ledger entry exists. The source migration is on `main`; a teacher-JWT success path was not smoke-tested in this audit. |
| Stage 7 shared client contract | `api-contracts.ts`, API error normalizer, frontend integration and OpenAPI docs. | No new privileged endpoint; client uses publishable key + user JWT only. | Added here; OpenAPI marks source-only/nondeployed features explicitly. |

## Authorization/ownership matrix

| Operation | Authenticated role | Server-side ownership predicate | Client-exposed identity/data |
|---|---|---|---|
| Read profile | Student/teacher | `profiles.user_id = auth.uid()`; teacher access to enrolled students is policy-limited. | Own role/display name; do not accept a frontend-supplied role. |
| Create class | Teacher | `teacher_id` is derived from `auth.uid()`; caller must have teacher profile. | Class metadata. |
| Enroll student | Teacher | Class must be owned by caller; target profile must be student. | Student UUID is an input, never authorization. |
| Assessment list/retrieve/start | Student | Published/open template or active class enrollment. | Questions/choices; answer key and post-submit guidance withheld. |
| Save/complete attempt | Student | Attempt belongs to caller and is editable; question belongs to the attempt. Server grades using private keys. | Request contains answer JSON only; no score/correctness fields. |
| Get result/diagnosis | Student | Own graded attempt. | Own result/evidence only; diagnosis remains candidate/uncertain. |
| Teacher class analytics | Teacher | Class owner; class/assessment pair must match; student detail additionally checks enrollment. | Class aggregates; student detail is scoped. Report excludes identities and answer payloads. |
| Stage 4 AI services | Student | JWT checked; own graded attempt; question belongs to attempt; activity lookup keyed by student. | Only requested IDs/answer; key and provider secrets server-side. |
| Stage 5 progress | Student/teacher | Session-derived student; owning class for teacher aggregate. | Not live until migration deployed. |

RLS and SQL authorization are defense in depth. Frontend filtering must not be used as an access-control mechanism. Do not treat an empty RLS-filtered table response as proof that the requested row does not exist.

## Database security observations

The connected project has public RLS enabled on the inspected tables. Supabase returned a critical advisory that RLS is disabled on `private.misconception_rules`, `private.ai_request_buckets`, `private.ai_learning_activities`, and `private.ai_practice_responses`. The private schema is excluded from the configured exposed API schemas; Stage 4 source uses server-side/service-only access. Nevertheless, the database advisory states these tables may be reachable to `anon`/`authenticated` by grants. Review actual grants and service access before production use. Enabling RLS alone would block legitimate service operations, so design explicit policies and integration tests before remediation; no policy change is included in Stage 7.

The remote migration ledger ends at Stage 4 (`20261030194703`), while metadata shows Stage 6 functions installed and Stage 5 absent. Local Stage 3 (`20261028093000`) and Stage 4 (`20261029222500`) source filenames do not match the remote ledger versions (`20261028101421` and `20261030194703`). Treat this as deployment drift requiring controlled reconciliation; do not blindly reapply Stage 6, rename applied source migrations casually, or use a fake migration repair entry. Stage 5 could not be deployed from this environment because no Supabase CLI, PostgreSQL client, CLI auth token, or file-backed migration connector was available. The migration source was not truncated or reconstructed and no partial SQL was sent.

## Error/response standardization

Wire responses remain backward-compatible:

- PostgREST database errors are `{code,message,details,hint}` and retain SQLSTATE.
- Edge Function source uses `{error:{code,message}}`; some 503 AI responses also contain `fallback` and `source`.
- The frontend adapter maps these to the stable `ApiError` shape in `api-contracts.ts`, with category/status/retryability and generic safe copy. Raw DB detail/hint is not UI copy.
- SQLSTATE `22023` is context-sensitive; treat as validation by default rather than assuming not-found. Authorization failures (`42501`) must not reveal foreign class/student existence.

## Test and verification boundaries

Stage 6 includes aggregate/RLS pgTAP tests and static contract tests. Stage 4 has mocked handler/validator tests and migration contract tests on the integration branch. Stage 7 adds error-category tests and OpenAPI static checks. None of those proves a teacher-authenticated remote success path or that the current remote migration ledger matches source. `supabase test db` was not available because the desktop has no Supabase CLI/psql and Docker is not running. See the final Stage 7 report for executed checks.
