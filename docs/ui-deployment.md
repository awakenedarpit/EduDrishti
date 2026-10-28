# EduDrishti web app setup and Vercel deployment

The frontend lives in `web/` and is a static Vite/React/TypeScript application. The browser calls the existing Supabase Auth and assessment APIs with the public anon/publishable key; PostgreSQL RLS, RPCs, and database-provisioned profiles remain authoritative. No Vercel deployment or database migration is performed by this guide.

## Local development

Use Node.js 20.19+ or 22.12+ (Vite 7 requirement) and pnpm 12.15.0. From this directory:

```sh
cd web
pnpm install --frozen-lockfile
cp .env.example .env.local
```

Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in `web/.env.local` to the intended Supabase project's API URL and anon/publishable key, then run:

```sh
pnpm dev
pnpm typecheck
pnpm test
pnpm build
```

The development server defaults to `http://127.0.0.1:5173`. Do not overwrite an existing `.env.local`; edit only the two browser-safe values. Local environment files and build outputs are ignored by Git.

## Deploy to Vercel

1. Import the existing EduDrishti Git repository into Vercel. Select **`web`** as the Root Directory and enable inclusion of files outside the root only if Vercel requests it; the frontend itself is self-contained under `web/`.
2. Select the Vite framework preset. Use the pinned `pnpm@12.15.0` package manager, install command `pnpm install --frozen-lockfile`, build command `pnpm build`, and output directory `dist`.
3. Add these Environment Variables for Preview and Production (and Development if desired):
   - `VITE_SUPABASE_URL` — the Supabase project URL.
   - `VITE_SUPABASE_ANON_KEY` — that project's public anon/publishable key.
4. Deploy from Vercel. `web/vercel.json` rewrites app routes to the SPA entry point so pages such as `/attempts/<id>/results` work on direct navigation.
5. In Supabase Authentication → URL Configuration, set the Site URL to the production Vercel domain. Add the exact Vercel Preview/production origins you use to the allowed redirect URLs. If a custom domain is configured, add it as well. Email confirmation behavior is controlled by the Supabase project's Auth settings.

A Supabase anon/publishable key is designed to be public, but it is not an authorization boundary. Do not place a service-role key, database password, or other privileged secret in `VITE_*` variables: Vite embeds those values in downloadable browser assets. Keep RLS enabled and use the existing authenticated RPCs.

## Connected screens and current limits

- Sign-in and student signup use Supabase Auth. The existing Auth trigger provisions the profile; this interface never lets a user choose or self-assign the teacher role.
- Student assessment discovery, question retrieval, attempt start/resume, typed response saves, completion, and result/report history call the existing Stage 1/2 database paths. Correctness and points are calculated by PostgreSQL. The screen does not reveal keys before a graded result.
- Teachers can list their own RLS-scoped classes and create a class through the existing trusted RPC. The database sets ownership from the session.
- Every other supplied Stitch destination is present as a labeled placeholder. In particular, student diagnosis and the teacher misconception heatmap stay marked **Not connected** until the Stage 3 migration/RPCs are actually installed in the chosen Supabase database. The dashboard does not fabricate learner identities, performance values, or diagnosis summaries.

The deployed website uses the Supabase schema and Auth configuration already present in the chosen project. This UI guide does not apply migrations. Confirm that Stage 1 and Stage 2 are deployed before using live workflows; do not use production learner accounts to test signup or assessment flows.
