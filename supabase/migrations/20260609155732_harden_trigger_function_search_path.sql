-- Security Advisor: Function Search Path Mutable
--
-- These trigger functions were hardened in an earlier migration, but later
-- CREATE OR REPLACE FUNCTION statements reset their function-level settings.
-- Keep the final schema explicit so Supabase does not execute them with a
-- caller-controlled search_path.

ALTER FUNCTION public.set_updated_at()
  SET search_path = public, pg_temp;

ALTER FUNCTION public.recalculate_milestone_progress()
  SET search_path = public, pg_temp;

ALTER FUNCTION public.recalculate_plan_progress()
  SET search_path = public, pg_temp;
