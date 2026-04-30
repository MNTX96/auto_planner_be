-- Fix Security Advisor warnings:
-- 1. Function Search Path Mutable → add SET search_path = '' to all trigger functions
-- 2. Public/Signed-In Can Execute SECURITY DEFINER → revoke execute from public/authenticated on trigger functions

-- ============================================================
-- 1. set_updated_at — no table refs, just fix search_path
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. set_task_completed_at — no table refs, just fix search_path
-- ============================================================
CREATE OR REPLACE FUNCTION set_task_completed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    NEW.completed_at = NOW();
  ELSIF NEW.status != 'completed' AND OLD.status = 'completed' THEN
    NEW.completed_at = NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. recalculate_milestone_progress — fully qualify table refs
-- ============================================================
CREATE OR REPLACE FUNCTION recalculate_milestone_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_milestone_id UUID;
  v_total        INTEGER;
  v_completed    INTEGER;
  v_progress     INTEGER;
BEGIN
  v_milestone_id := COALESCE(NEW.milestone_id, OLD.milestone_id);

  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE status = 'completed')
  INTO v_total, v_completed
  FROM public.tasks
  WHERE milestone_id = v_milestone_id;

  v_progress := CASE
    WHEN v_total = 0 THEN 0
    ELSE ROUND((v_completed::NUMERIC / v_total) * 100)
  END;

  UPDATE public.milestones
  SET progress_percentage = v_progress
  WHERE id = v_milestone_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- 4. recalculate_plan_progress — fully qualify table refs
-- ============================================================
CREATE OR REPLACE FUNCTION recalculate_plan_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_plan_id  UUID;
  v_progress INTEGER;
BEGIN
  v_plan_id := COALESCE(NEW.plan_id, OLD.plan_id);

  SELECT COALESCE(ROUND(AVG(progress_percentage)), 0)
  INTO v_progress
  FROM public.milestones
  WHERE plan_id = v_plan_id;

  UPDATE public.plans
  SET progress_percentage = v_progress
  WHERE id = v_plan_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- 5. handle_new_user — already has SET search_path = public; revoke direct execution
--    It is a trigger function — only the trigger runtime should call it.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- ============================================================
-- 6. save_plan_transaction — revoke from anon (public), keep for authenticated
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) TO authenticated;

-- ============================================================
-- 7. rls_auto_enable — Supabase system function; revoke public execute if it exists
-- ============================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'rls_auto_enable'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;
  END IF;
END;
$$;
