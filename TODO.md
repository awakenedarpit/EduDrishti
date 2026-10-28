# EduDrishti UI Integration — TODO

- [x] **Stitch shell and complete destination set.** Acceptance criteria: “This is the reference UI.” “Include all Stitch screens as clearly labeled placeholders.” Build the responsive EduDrishti navigation and visual shell from the attached Stitch ZIP; make every supplied student and teacher destination navigable. Connect only supported features and clearly label unsupported screens as “Coming soon” or “Not connected.” Do not present invented learner identities, scores, diagnoses, or analytics as real data.

- [x] **Connect the existing application features.** Acceptance criteria: “Attach the existing Features with this user interface.” Integrate Supabase Auth using the server-provisioned `profiles.app_role`, without a client-side teacher role selector or promotion path. Connect student assessment discovery, question retrieval, attempt start, typed answer saves, server-side completion/grading, and own-result retrieval to the existing RPCs. Connect the teacher’s RLS-scoped class list and class creation path. Keep answer keys and scoring on the server; show diagnosis capabilities as unavailable until the Stage 3 RPCs exist remotely.

- [x] **Make the frontend deployable on Vercel.** Acceptance criteria: “make it deployable on Vercel.” Provide a self-contained Vite/React/TypeScript project in `web/`, SPA deep-link routing, pinned package-manager metadata and lockfile, browser-safe Supabase environment placeholders, a route manifest, a Vercel build configuration, and concise deployment instructions. Keep service-role and other trusted secrets out of browser bundles and require no remote migration or public deployment for this task.

## Outcome

The frontend implementation and local validation are complete. It is prepared for Vercel; no Vercel deployment or Supabase schema change was performed. The user-requested GitHub push is limited to the UI deliverables; unrelated Stage 3 work remains uncommitted.
