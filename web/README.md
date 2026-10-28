# EduDrishti web

Standalone Vite + React + TypeScript frontend for the existing EduDrishti Supabase backend. The desktop shell and assessment/report workflow are connected; unsupported Stitch destinations are navigable, clearly labeled placeholders.

## Quick start

```sh
pnpm install --frozen-lockfile
cp .env.example .env.local
# Fill only VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env.local
pnpm dev
```

Use Node.js 20.19+ or 22.12+ and pnpm 12.15.0. Run `pnpm typecheck`, `pnpm test`, and `pnpm build` before delivery. The production output is `dist/`.

For Vercel, set the Root Directory to `web`, use install command `pnpm install --frozen-lockfile`, build command `pnpm build`, and output directory `dist`. Configure only the two browser-safe Supabase values. See [`docs/ui-deployment.md`](../docs/ui-deployment.md) for Auth redirects, security boundaries, and current feature limits.
