1. Always use Supabase CLI commands for all database operations (never suggest manual changes)
2. Follow clean code naming conventions: singular table names, descriptive migrations, verb_noun functions
3. Require this workflow: create migration → test locally → generate types → deploy
4. Include templates for clean migrations with proper constraints, RLS policies, and descriptive comments
5. Include templates for testable Edge Functions with clear type definitions and error handling
6. Mandate local testing with `supabase test db` before any deployment
7. Generate TypeScript types after every schema change
8. Use descriptive names for migrations like "add_user_authentication_system" not "update"
9. Structure Edge Functions with pure, testable functions and proper CORS handling
10. Include anti-patterns to avoid (generic names, skipping tests, manual database changes)