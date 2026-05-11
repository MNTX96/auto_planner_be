-- Fix save_plan_transaction after the singular table migration accidentally
-- stopped inserting required milestone/task ordering columns.

CREATE OR REPLACE FUNCTION save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_plan_id UUID;
  v_ms JSONB;
  v_ms_index INTEGER;
  v_task JSONB;
  v_task_index INTEGER;
  v_ms_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO plan (
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
    start_date,
    end_date,
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
    (payload->>'start_date')::DATE,
    (payload->>'end_date')::DATE,
    COALESCE(payload->'success_metrics', '[]'::jsonb),
    COALESCE(payload->'expert_advice', '{}'::jsonb)
  )
  RETURNING id INTO v_plan_id;

  FOR v_ms, v_ms_index IN
    SELECT value, ordinality::INTEGER
    FROM jsonb_array_elements(payload->'milestones') WITH ORDINALITY
      AS milestones(value, ordinality)
  LOOP
    INSERT INTO milestone (
      plan_id,
      milestone_index,
      name,
      focus_objective,
      start_date,
      end_date
    ) VALUES (
      v_plan_id,
      COALESCE(NULLIF(v_ms->>'milestone_index', '')::INTEGER, v_ms_index),
      v_ms->>'name',
      v_ms->>'focus_objective',
      (v_ms->>'start_date')::DATE,
      (v_ms->>'end_date')::DATE
    )
    RETURNING id INTO v_ms_id;

    FOR v_task, v_task_index IN
      SELECT value, ordinality::INTEGER
      FROM jsonb_array_elements(v_ms->'tasks') WITH ORDINALITY
        AS tasks(value, ordinality)
    LOOP
      INSERT INTO task (
        milestone_id,
        user_id,
        task_index,
        name,
        scheduled_start,
        scheduled_end,
        duration_minutes,
        resources_or_location,
        details,
        task_type
      ) VALUES (
        v_ms_id,
        v_user_id,
        COALESCE(NULLIF(v_task->>'task_index', '')::INTEGER, v_task_index),
        v_task->>'name',
        (v_task->>'scheduled_start')::TIMESTAMPTZ,
        (v_task->>'scheduled_end')::TIMESTAMPTZ,
        NULLIF(v_task->>'duration_minutes', '')::INTEGER,
        v_task->>'resources_or_location',
        v_task->>'details',
        'ai_plan'
      );
    END LOOP;
  END LOOP;

  RETURN v_plan_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION save_plan_transaction(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_plan_transaction(JSONB) TO authenticated;
