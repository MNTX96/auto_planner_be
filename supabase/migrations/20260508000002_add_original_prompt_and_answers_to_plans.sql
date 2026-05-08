-- Add original_prompt and answers columns to plans for regeneration support.
-- The new generate-plan API separates the user's raw prompt from the structured
-- answers collected via dynamic questions, so we persist both for later regeneration.

ALTER TABLE public.plans
  ADD COLUMN IF NOT EXISTS original_prompt TEXT,
  ADD COLUMN IF NOT EXISTS answers         JSONB DEFAULT '{}'::jsonb;

-- Recreate save_plan_transaction to persist the two new fields.
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
    original_prompt,
    answers,
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
    payload->>'original_prompt',
    COALESCE(payload->'answers', '{}'::jsonb),
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

REVOKE EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) TO authenticated;
