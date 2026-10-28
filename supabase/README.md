# Supabase backend workspace

This directory is reserved for future Supabase configuration, reviewed SQL migrations, and Edge Functions. Stage 0 does not initialize a Supabase project or add a schema, policy, or function.

When implementation begins, use migrations as the source of truth for database changes, test RLS authorization paths, and keep privileged keys such as the service-role key and Gemini API key in Supabase's server-side secret store. Do not commit local Supabase state or credentials.
