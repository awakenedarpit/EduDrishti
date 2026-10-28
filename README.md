# EduDrishti Learner Intelligence

EduDrishti is an AI-powered adaptive learning platform intended to help students understand where they are struggling, receive targeted explanations and practice, and help teachers identify learning needs across a class.

## Product direction

The initial learning domain is Class 10 Mathematics, beginning with Quadratic Equations. The planned MVP includes a student dashboard, diagnostic assessment, misconception detection, personalized explanations, generated practice, mastery tracking, teacher/classroom analytics, and assessment reports. These are product goals, not implemented features in this foundation.

## Current stage

This repository contains the Stage 0 project foundation only. It deliberately does not implement application features or recreate the separately generated Google Stitch frontend. Frontend code will be integrated when supplied.

## Intended architecture

- **Database:** Supabase PostgreSQL, with schema changes managed as reviewed SQL migrations.
- **Authentication and authorization:** Supabase Auth with PostgreSQL Row Level Security (RLS). RLS policies are required before student or classroom data is exposed.
- **Secure backend operations:** Supabase Edge Functions for trusted operations, including calls to external AI services.
- **AI:** Gemini API, called server-side from Edge Functions. Provider keys must never be bundled into browser code.
- **Frontend:** Google Stitch-generated client, to be supplied separately and connected using only the Supabase project URL and publishable/anon key.
- **Deployment:** Vercel is a possible frontend hosting target; Supabase remains the managed database, auth, and edge-function platform.

See [docs/architecture.md](docs/architecture.md) for the integration boundaries and security principles.

## Repository layout

```text
.
├── docs/
│   ├── architecture.md
│   └── development.md
├── supabase/
│   └── README.md
└── tests/
    └── test_foundation.py
```

## Local setup

1. Clone the agreed GitHub repository once it has been created and access is available.
2. Copy `.env.example` to a local `.env` file and replace placeholders only with credentials for your own development project. `.env` is ignored by Git.
3. Do not put Supabase service-role keys or Gemini API keys in frontend environment variables or browser code. Those secrets belong in Supabase Edge Function secrets when backend implementation begins.
4. Review [docs/development.md](docs/development.md) before adding code or connecting real student data.

No application runtime, dependencies, Supabase project, or credentials are created by this Stage 0 scaffold.

## Validation

The foundation uses Python's standard library for its initial checks; no Python packages are needed:

```sh
python3 -m unittest discover -s tests -v
```

Run this after documentation or configuration changes. Backend changes should later add migration validation, RLS/authorization tests, and Edge Function tests before deployment.

## Development workflow

Keep changes small and reviewable. Use SQL migrations for database changes; define and test RLS policies alongside tables; keep privileged operations and AI calls in Edge Functions; and integrate the Stitch frontend only when its source is provided. Before any deployment involving student data, establish the applicable consent, privacy, retention, and incident-response requirements.
