-- Fix remaining Security Advisor warnings:
-- "Public/Signed-In Can Execute SECURITY DEFINER Function"

-- ============================================================
-- handle_new_user: trigger-only function — revoke direct execution
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- ============================================================
-- rls_auto_enable: Supabase system function — revoke public execute
-- ============================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'rls_auto_enable'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;
  END IF;
END;
$$;

-- ============================================================
-- save_plan_transaction: drop SECURITY DEFINER entirely.
-- RLS policies already restrict each user to their own rows,
-- so SECURITY DEFINER is unnecessary and causes the warnings.
-- ============================================================
CREATE OR REPLACE FUNCTION public.save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_plan_id UUID;
  v_ms      JSONB;
  v_task    JSONB;
  v_ms_id   UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.plans (
    user_id,
    domain,
    prompt_goal,
    prompt_current_status,
    prompt_available_time,
    prompt_constraints,
    title,
    ultimate_goal,
    total_duration,
    success_metrics,
    expert_advice
  ) VALUES (
    v_user_id,
    payload->>'domain',
    payload->>'prompt_goal',
    payload->>'prompt_current_status',
    payload->>'prompt_available_time',
    payload->>'prompt_constraints',
    payload->>'title',
    payload->>'ultimate_goal',
    payload->>'total_duration',
    COALESCE(payload->'success_metrics', '[]'::jsonb),
    COALESCE(payload->'expert_advice',   '{}'::jsonb)
  )
  RETURNING id INTO v_plan_id;

  FOR v_ms IN SELECT value FROM jsonb_array_elements(payload->'milestones')
  LOOP
    INSERT INTO public.milestones (plan_id, milestone_index, name, focus_objective)
    VALUES (
      v_plan_id,
      (v_ms->>'milestone_index')::INTEGER,
      v_ms->>'name',
      v_ms->>'focus_objective'
    )
    RETURNING id INTO v_ms_id;

    FOR v_task IN SELECT value FROM jsonb_array_elements(v_ms->'tasks')
    LOOP
      INSERT INTO public.tasks (
        milestone_id,
        task_index,
        task_time,
        name,
        duration_minutes,
        resources_or_location,
        details
      ) VALUES (
        v_ms_id,
        (v_task->>'task_index')::INTEGER,
        v_task->>'task_time',
        v_task->>'name',
        NULLIF(v_task->>'duration_minutes', '')::INTEGER,
        v_task->>'resources_or_location',
        v_task->>'details'
      );
    END LOOP;
  END LOOP;

  RETURN v_plan_id;
END;
$$;

-- Restrict execution: anon users must not call this RPC
REVOKE EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) TO authenticated;
