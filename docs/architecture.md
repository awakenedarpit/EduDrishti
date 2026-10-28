# Intended architecture

This document describes the planned MVP boundaries. It is an implementation guide, not a claim that the services or features have already been configured.

## System overview

```text
Google Stitch frontend (supplied separately)
        │ Supabase URL + publishable/anon key; authenticated user JWT
        ▼
Supabase Auth ── issues identity and session
        │
        ├── PostgreSQL + Row Level Security
        │     └── learner progress, assessments, practice, classroom data
        │
        └── Supabase Edge Functions
              ├── validate user/session and authorize the requested operation
              ├── read/write only the data needed for that operation
              └── call Gemini using a server-side secret
```

Vercel may host the separately supplied frontend. Supabase is the intended home for authentication, PostgreSQL, and Edge Functions. Avoid introducing additional services unless an identified requirement justifies them.

## Trust boundaries and responsibilities

- The browser is an untrusted client. It may use the Supabase project URL and publishable/anon key, but must never contain a service-role key, database password, Gemini key, or other privileged credential.
- Supabase Auth establishes identity; it does not by itself authorize access to a particular learner or classroom record.
- PostgreSQL RLS is the primary data-access boundary. Policies should default to denial and be tested for both allowed and denied cases. Do not rely on frontend checks as authorization.
- Edge Functions should validate authentication, authorization, input shape, and resource limits before accessing data or calling Gemini. Store privileged credentials in the platform's server-side secret store.
- AI output is untrusted content. Validate and constrain output before presenting it or using it to affect assessment or mastery records. Provide a human-teacher path for review where appropriate.

## Data and domain direction

The first learning domain is Class 10 Mathematics: Quadratic Equations. Later schema design may need concepts, learning objectives, questions, attempts, misconception signals, practice items, mastery evidence, learners, teachers, and classroom membership. Stage 0 intentionally creates no tables or policies: data relationships, retention, and authorization rules should be specified before a migration is written.

Use stable identifiers and explicit relationships; collect only data needed for learning outcomes. Avoid putting identifiable student information in application logs, prompts, analytics, or test fixtures. Use synthetic data for development.

## Frontend integration contract

When Stitch-generated code is supplied:

1. Inspect its framework, runtime, dependencies, and existing conventions before integrating it.
2. Keep browser configuration limited to the project URL and publishable/anon key.
3. Use authenticated Supabase clients and let RLS enforce row access.
4. Route privileged workflows and Gemini requests through Edge Functions with documented request/response types.
5. Treat service-role credentials as server-only; never expose them through `VITE_*`, `NEXT_PUBLIC_*`, source maps, or client bundles.

Agree on API and data contracts before wiring screens to backend behavior. Do not recreate the UI as part of this foundation stage.

## Deployment and student-data readiness

Keep development, staging, and production credentials separate. Review database migrations and authorization tests before applying them to shared environments. Before processing real student data, determine applicable consent, privacy, retention/deletion, and incident-response requirements for the deployment jurisdictions and users. This document is not legal advice or a compliance certification.
