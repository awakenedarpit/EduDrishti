# Diagnostic assessment engine

## Scope and content

Stage 2 provides a database-backed diagnostic assessment flow for Class 10 Mathematics, initially Quadratic Equations. The sample items cover standard form and factorisation, real roots, discriminant/nature of roots, and one contextual quadratic problem. These topics appear in the current CBSE Class X Mathematics syllabus and the NCERT Class 10 Quadratic Equations chapter. [1] [2]

The seven-question assessment and its questions are labeled `development_fixture`. They are reviewed educational examples, not official exam questions and not student-performance records. The scored sample is published as a template accessible only to authenticated accounts whose application role is `student`. Class-specific assessments remain limited to active class enrollments and their owning teacher.

## Stored data and answer privacy

`questions` stores prompt, question type, options, topic, difficulty (1–5), concept, and content source. `question_answer_keys` stores answer and grading configuration. `question_guidance` stores explanations and misconception tags. RLS prevents student reads of answer keys and guidance. The assessment-retrieval RPC returns options and question metadata but omits correct answers, explanations, and misconception tags. The completed-results RPC reveals those details only to the student who owns the graded attempt.

Question formats are strict JSON objects:

- `single_choice`: `{"selected_option":"B"}`; the option id must exist.
- `multiple_choice`: `{"selected_options":["A","D"]}`; ids must be distinct and valid. Order does not matter.
- `numeric`: `{"value":1.5}`; the value must be a JSON number.
- `short_text`: `{"value":"x^2 - 5x + 6 = 0"}`; comparison is exact after lowercasing and removing whitespace, against server-stored accepted answers.

The client cannot supply correctness, points, feedback, or a score. Single-choice, multiple-choice, numeric, and short-text items are all-or-nothing. A multiple-choice item receives its full point value only when the selected set exactly matches the key; there is no partial credit. Numeric answers use a per-question server-side tolerance. Unanswered items are materialized at completion as unanswered response rows and earn zero points. The attempt score is `round(100 × earned_points / total_points, 2)` using the assessment's positive point weights.

Starting an assessment is idempotent while an attempt is in progress: repeated starts return that attempt. Saving the same question again updates the existing ungraded response rather than creating a duplicate. Completion locks the attempt, grades it once, and returns the same result summary on subsequent calls. Attempts can be repeated after completion; a new start creates the next numbered attempt. Incomplete attempts can be completed and are scored with unanswered items counted as zero.

## Authenticated RPC contract

The PostgREST Data API exposes PostgreSQL functions at `/rest/v1/rpc/<function_name>`. Supabase client libraries call them through `supabase.rpc(...)`. [3] [4] Send the user's Supabase access token; all student operations require a provisioned `student` profile.

1. **List available assessments — `list_available_assessments()`**

   Takes no arguments. Returns a JSON array of published, currently open assessments available to the student, with id, title, type, class/template marker, question count, total points, and open/close timestamps. It includes the development template and assessments for the student's active enrollments.

2. **Retrieve an assessment — `get_assessment({"p_assessment_id":"<uuid>"})`**

   Returns `{schema_version, assessment, questions}`. Questions are ordered and include id, position, points, type, prompt, options, difficulty, concept, and topic metadata. It does not return answer keys, explanations, or misconception tags.

3. **Start an attempt — `start_assessment({"p_assessment_id":"<uuid>"})`**

   Returns an attempt UUID. The server checks that the assessment is published/open and that the caller is a student authorized by template access or active enrollment. Repeating the call during an active attempt returns the same UUID.

4. **Save or replace an answer — `save_response({"p_attempt_id":"<uuid>","p_question_id":"<uuid>","p_answer":{...}})`**

   Returns the response UUID. The database verifies ownership, active-attempt state, question membership, answer shape, option ids, and a 16 KiB payload limit. It does not reveal whether an answer is correct.

5. **Complete and grade — `complete_assessment({"p_attempt_id":"<uuid>"})`**

   Returns the completed result summary below. The operation is atomic and idempotent. The legacy `submit_assessment({"p_attempt_id":"<uuid>"})` remains as a void-returning compatibility alias to the same server grading path; new clients should call `complete_assessment`.

6. **Retrieve own completed result — `get_student_results({"p_attempt_id":"<uuid>"})`**

   Returns the same summary only when the caller owns an attempt in `graded` state. Requests for another student's attempt are denied; results are not available before completion.

The completed summary is versioned and shaped for future report screens:

```json
{
  "schema_version": 1,
  "attempt": {
    "id": "<uuid>",
    "assessment_id": "<uuid>",
    "assessment_title": "Quadratic Equations Diagnostic (Development Sample)",
    "attempt_number": 1,
    "status": "graded",
    "started_at": "<timestamp>",
    "submitted_at": "<timestamp>",
    "score_percent": 71.43
  },
  "summary": {
    "earned_points": 5,
    "total_points": 7,
    "correct_count": 5,
    "incorrect_count": 1,
    "unanswered_count": 1
  },
  "items": [
    {
      "question_id": "<uuid>",
      "position": 1,
      "question_type": "single_choice",
      "prompt": "...",
      "answer": {"selected_option": "B"},
      "is_answered": true,
      "is_correct": true,
      "score_percent": 100,
      "points_earned": 1,
      "points_possible": 1,
      "correct_answer": {"correct_option": "B"},
      "explanation": "...",
      "misconception_tags": ["factor_pair_error"]
    }
  ]
}
```

PostgREST errors retain the database SQLSTATE in `code` and include `message`, `details`, and `hint`. Stable codes used by these RPCs include `28000` for missing authentication, `42501` for authorization failure, `22023` for invalid question/answer input, and `55000` for an invalid attempt or assessment state. Do not treat the error message as a substitute for checking the code.

## Test and deployment notes

The pgTAP suite under `supabase/tests/rls.test.sql` covers student and teacher boundaries plus Stage 2 validation, state, idempotency, score, and persistence paths. Local Python tests inspect migration/API contracts only and do not execute PostgreSQL. Remote Supabase smoke tests are reported separately. Seeded question-bank data is not learner data; test attempts use transaction-scoped synthetic identities and are rolled back.

## References

[1]: https://cbseacademic.nic.in/web_material/CurriculumMain27/SecPart1/Maths_SecP1X_2026-27.pdf "CBSE Class X Mathematics Curriculum 2026–27"
[2]: https://ncert.nic.in/textbook/pdf/jemh104.pdf "NCERT Mathematics Class X, Quadratic Equations"
[3]: https://supabase.com/docs/guides/database/functions "Supabase Database Functions"
[4]: https://supabase.com/docs/guides/api/rest "Supabase Data REST API"
