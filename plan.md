# EduDrishti UI Integration Plan

## Goal and scope

Add a responsive, Vercel-deployable web companion under `web/` that adapts the supplied Stitch EduDrishti shell and connects to the existing Supabase Auth, assessment, result, and teacher-class capabilities. This is a plain-local project targeting Vercel; it will not use Manus-managed website services. No Supabase migration or public deployment is part of this UI task. The user-requested commit/push is limited to the UI deliverables and excludes unrelated Stage 3 work.

## Design

Use the reference's calm academic dashboard language: pale mint/soft paper surfaces, deep readable ink, forest-teal primary actions, restrained warm amber for emphasis, spacious card layouts, an anchored navigation rail on desktop, and a compact mobile navigation. Use Plus Jakarta Sans for headings and Inter for body/math content, with accessible contrast, clear focus states, responsive option tiles, and quiet transitions. Consolidate the reference pack's color variations into one consistent palette while preserving its recognizable EduDrishti shell and assessment interaction patterns.

The design movement is contemporary editorial minimalism with calibrated analytical depth. Core principles are clarity over clutter, cognitive ergonomics, evidence before inference, and constructive learning momentum. The pale mint canvas and white cards reduce visual strain; forest teal signals trusted navigation and action, with amber/blue accents reserved for progress or emphasis and red reserved for errors. A persistent desktop rail frames a wide working canvas; on small screens it becomes a compact menu. Signature elements are the teal active-navigation marker, softly layered analytical cards, and clear step/progress tracks. Interactions acknowledge server saves before navigation; answer selection has an immediate visible state, but correctness appears only after grading. Use restrained 160–220ms state transitions and honor reduced-motion preferences. Use Plus Jakarta Sans for editorial headings and Inter for transactional UI, with formulas set in a readable, non-condensed style. Brand essence: a clear-eyed, supportive, precise learning companion for students and teachers. Voice: specific and encouraging (“One clear step at a time.”, “Your result is ready to review.”), never claiming more than the evidence supports. The wordmark pairs a custom rounded forest-teal “E” monogram with the EduDrishti name; forest teal `#006b5b` is the signature brand color.

## Existing backend integration

- Use browser-safe Supabase URL and anon/publishable key only. Never bundle a service-role key or trusted server secret.
- Authenticate with Supabase Auth; after sign-in, read the server-provisioned `profiles.app_role`. Sign-up is student-only by default and exposes no role selector or client-side teacher promotion.
- Student assessment screens call `list_available_assessments`, `get_assessment`, `start_assessment`, `save_response`, `complete_assessment`, and `get_student_results`.
- Questions and answer choices are retrieved from PostgreSQL RPCs. Correct answers, explanations, misconception labels, and scores remain hidden until the server returns a completed result. The frontend submits only typed answer JSON and never computes correctness or points.
- The teacher home/class surfaces use the existing RLS-scoped class list and `create_class` RPC. Assessment management, rosters, student insights, reports, and analytics remain placeholders. The UI role gate is convenience only, with database policies/RPCs remaining authoritative.
- Diagnosis UI may call the Stage 3 RPCs only as an optional capability. Since Stage 3 is not applied remotely, show a clear unavailable/setup state rather than inventing learner diagnoses or aggregate metrics.
- Include every supplied Stitch destination: learner dashboard, assessments, diagnosis, learning hub, AI tutor, practice, study plan, progress, reports, personalized explanations, concept hub, teacher dashboard, class management, student insights, assessment management, analytics/misconception heatmap, practice allocator, teaching insights, and teacher reports/transcripts. Only existing data-backed flows are interactive; unsupported destinations remain navigable, clearly labeled “Coming soon” or “Not connected,” and show no fabricated learner identities, scores, diagnoses, or analytics.

## Project structure

- `web/`: standalone Vite + React + TypeScript frontend and Vercel project root.
- `web/src/app/`: routing, app shell, role-aware navigation, and auth/session state.
- `web/src/features/assessments/`: RPC client calls, validated answer state, assessment runner, and result/report views.
- `web/src/features/teacher/`: RLS-scoped class list and class creation surface.
- Diagnosis destinations use `web/src/features/placeholders/` until the Stage 3 RPCs are deployed; no diagnosis adapter is advertised as connected.
- `web/src/features/placeholders/`: branded, accessible placeholder pages for all other Stitch destinations, without simulated learner data.
- `web/src/lib/`: Supabase client, error normalization, typed RPC helpers, and environment validation.
- `web/src/styles/`: design tokens, responsive shell, and reusable components.
- `web/public/manus-routes.json`: route manifest synchronized with the app's page routes.
- `web/vercel.json`: SPA deep-link fallback for the Vite output.
- `web/.env.example`: browser-safe Supabase configuration placeholders and Vercel setup guidance.
- `docs/ui-deployment.md`: local setup, security boundary, and Vercel import/configuration steps.

## Vercel delivery shape

Set the Vercel project's Root Directory to `web`; use the pinned pnpm toolchain, `pnpm install --frozen-lockfile`, and `pnpm build`, publishing `dist`. Configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel's environment settings. The frontend remains a static client app backed by Supabase; no service-role secret is needed in the build. Vercel deployment itself is not requested here, so the deliverable is deployable source/configuration and instructions, not a published URL.
