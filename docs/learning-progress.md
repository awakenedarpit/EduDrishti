# Learning progress and mastery (Stage 5)

Stage 5 adds persisted, dated progress snapshots and read-only progress APIs. Assessment attempts and private targeted-practice responses remain the source of truth; progress rows are derived observations and never replace the underlying history. All new snapshots are labeled `mastery-v1` so a future calculation can be introduced under a different version without silently rewriting the meaning of existing records.

## `mastery-v1` baseline

The estimate is a transparent learning-progress indicator, not a scientifically calibrated ability score. It does not make causal claims about instruction or predict future performance.

Each evidence unit contributes a value of `1` for a correct response or `0` for an incorrect response. An assessment unit is one answered item from a server-graded attempt. Repeated graded attempts are preserved and count as separate dated evidence; ungraded attempts and unanswered items do not count.

A targeted-practice activity contributes one unit only after every generated item has at least one recorded answer. Its score is the unweighted fraction of its items correct, using the latest answer for each item at the time being evaluated. Re-answering an item updates that activity's result but does not add another evidence unit. Explanations and incomplete practice are activity history, not mastery evidence. Generic learning-session records are not counted by this model.

Evidence is grouped by the question's saved concept code within a published topic. Topic-level status pools the topic's assessment-item and completed-practice units. Rule-based diagnosis signals are included as a separate count only; they never change the accuracy calculation.

For a fixed as-of time, an evidence unit observed `d` days earlier receives weight `0.5^(d/90)`. The weighted accuracy is `sum(score × weight) / sum(weight)`. Only evidence observed within the preceding 90 days contributes to the current estimate. A status is shown only when there are at least five units over at least two distinct UTC calendar dates and the latest included evidence is within 90 days. Otherwise the state is `insufficient_evidence` and the percentage is `null`, not zero.

For sufficient evidence, below 60% is `emerging`, 60% through 79.9% is `developing`, and 80% or higher is `secure`. These thresholds are an initial descriptive baseline, not validated proficiency cutoffs. The 90-day recency half-life and five-unit/two-day minimum are fixed by `mastery-v1`; changing them requires a new calculation version and explicit migration/design review.

## Persistent history

`public.progress_records` is extended with a nullable topic-level estimate for insufficient evidence, the learning objective, topic-summary marker, version, status, evidence cutoff, compact evidence summary, and source event identity. A unique source-event/version index makes snapshot insertion idempotent. An assessment snapshot is inserted on the transition to `graded`; a practice snapshot is inserted once a complete practice activity has been answered and on subsequent answers after completion. The Stage 5 migration backfills versioned snapshots from already persisted Stage 2–4 events.

Snapshots are append-only interpretations of their dated evidence, not mutable “current score” rows. On a later formula change, retain old records under their original version and write new snapshots under a new version. Source attempts, responses, diagnosis records, and private AI activity responses remain authoritative.

## Student APIs

All student RPCs derive `auth.uid()` from the signed-in Supabase session and reject non-student profiles. Clients do not pass a student ID.

| RPC | Purpose |
| --- | --- |
| `get_student_progress_overview()` | Published topics, topic and objective status, evidence counts, supported diagnosis counts, and the active calculation version. Topics with no evidence are returned with `insufficient_evidence` and a null percentage. |
| `get_student_topic_mastery(p_topic_id uuid)` | One published topic's summary and concept-level breakdown. |
| `get_student_assessment_history(p_limit integer default 50)` | The latest attempts, preserving retries, dates, result counts, topic labels, and supported diagnosis counts; the total attempt count is separate from the page limit. The limit is 1–100. |
| `get_student_recent_learning_activity(p_limit integer default 20)` | Real assessment, explanation, and targeted-practice activity with completion state and actual item counts. The limit is 1–100. |
| `get_student_mastery_history(p_topic_id uuid, p_learning_objective text default null, p_limit integer default 50)` | Dated, version-tagged snapshots for the topic overall or one objective. The limit is 1–200. |
| `get_student_progress_comparison(p_period_days integer default 30, p_topic_id uuid default null)` | Compares the current period with the immediately preceding period of the same length. Each period applies the same 90-day evidence cutoff relative to its own end; for periods longer than 90 days, only each period's most recent 90 days contribute. A numeric change is returned only when both periods independently meet the evidence threshold; otherwise the response explicitly marks the comparison insufficient. Period length is 7–180 days. |

The React `/progress` screen uses the overview, comparison, and recent-activity RPCs. `/reports` uses the authorized assessment-history RPC. The learner dashboard shows a separate progress snapshot; assessment features remain usable if the progress RPC is not installed or fails.

## Teacher class summary

`get_class_learning_progress(p_class_id uuid, p_topic_id uuid default null)` is available only to the authenticated teacher who owns the class. It includes only assessments assigned to that class and learners with an active enrollment. It returns active enrollment counts, aggregate topic/objective accuracy, evidence counts and supported diagnosis counts; it deliberately omits student identifiers, names, and per-learner rows. It is not a learner ranking or a substitute for an authorized individual-support workflow. The `/teacher/analytics` page is role-gated and lets the teacher select only a class returned by the teacher-owned class-list API.

Progress snapshots use `class_id = NULL` and remain learner-private under the existing row-level policies. Teachers receive a separate aggregate RPC rather than direct access to student snapshot rows.

## Security and deployment

The migration is `supabase/migrations/20261030223000_stage5_learning_progress.sql`. Public RPCs are `SECURITY DEFINER`, use an empty `search_path`, validate the current role and ownership, and have explicit authenticated-only grants. Internal aggregation and snapshot functions are in the non-exposed `private` schema with execute revoked from browser and service roles. Authenticated clients have no direct insert/update permission on `progress_records`.

Review the target project and migration ledger before applying anything. Locally, use `supabase start`, `supabase db reset`, and `supabase test db` from the repository root. The Stage 5 transactional pgTAP suite is `supabase/tests/learning_progress.test.sql`. It covers status boundaries, one-answer insufficiency, repeated attempts, objective aggregation, completed-practice deduplication, dated comparisons/history, and student/teacher access. Python contract tests are static checks; they do not execute PostgreSQL. Frontend checks run from `web/` with `pnpm typecheck`, `pnpm test`, and `pnpm build`.

Stage 5 source code and tests are not evidence of remote deployment. The migration should not be applied remotely until the exact project and migration ledger have been checked and an authorized deployment is performed.
