-- Fix trigger functions to use singular table names
CREATE OR REPLACE FUNCTION recalculate_milestone_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
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
  FROM task
  WHERE milestone_id = v_milestone_id;

  v_progress := CASE
    WHEN v_total = 0 THEN 0
    ELSE ROUND((v_completed::NUMERIC / v_total) * 100)
  END;

  UPDATE milestone
  SET progress_percentage = v_progress
  WHERE id = v_milestone_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION recalculate_plan_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_plan_id  UUID;
  v_progress INTEGER;
BEGIN
  v_plan_id := COALESCE(NEW.plan_id, OLD.plan_id);

  SELECT COALESCE(ROUND(AVG(progress_percentage)), 0)
  INTO v_progress
  FROM milestone
  WHERE plan_id = v_plan_id;

  UPDATE plan
  SET progress_percentage = v_progress
  WHERE id = v_plan_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Ensure triggers are on the singular tables
DROP TRIGGER IF EXISTS tasks_update_milestone_progress ON tasks;
DROP TRIGGER IF EXISTS milestones_update_plan_progress ON milestones;

DROP TRIGGER IF EXISTS tasks_update_milestone_progress ON task;
CREATE TRIGGER tasks_update_milestone_progress
  AFTER INSERT OR UPDATE OF status OR DELETE ON task
  FOR EACH ROW
  EXECUTE FUNCTION recalculate_milestone_progress();

DROP TRIGGER IF EXISTS milestones_update_plan_progress ON milestone;
CREATE TRIGGER milestones_update_plan_progress
  AFTER INSERT OR UPDATE OF progress_percentage OR DELETE ON milestone
  FOR EACH ROW
  EXECUTE FUNCTION recalculate_plan_progress();

-- Updated-at triggers
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS plan_set_updated_at ON plan;
CREATE TRIGGER plan_set_updated_at BEFORE UPDATE ON plan FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS milestone_set_updated_at ON milestone;
CREATE TRIGGER milestone_set_updated_at BEFORE UPDATE ON milestone FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS task_set_updated_at ON task;
CREATE TRIGGER task_set_updated_at BEFORE UPDATE ON task FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Fix save_plan_transaction to use new columns and singular names
CREATE OR REPLACE FUNCTION save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_plan_id UUID;
  v_ms      JSONB;
  v_task    JSONB;
  v_ms_id   UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO plan (
    user_id,
    domain,
    prompt_goal,
    prompt_current_status,
    prompt_available_time,
    prompt_constraints,
    title,
    ultimate_goal,
    start_date,
    end_date,
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
    (payload->>'start_date')::DATE,
    (payload->>'end_date')::DATE,
    COALESCE(payload->'success_metrics', '[]'::jsonb),
    COALESCE(payload->'expert_advice',   '{}'::jsonb)
  )
  RETURNING id INTO v_plan_id;

  FOR v_ms IN SELECT value FROM jsonb_array_elements(payload->'milestones')
  LOOP
    INSERT INTO milestone (
      plan_id, 
      name, 
      start_date, 
      end_date
    )
    VALUES (
      v_plan_id,
      v_ms->>'name',
      (v_ms->>'start_date')::DATE,
      (v_ms->>'end_date')::DATE
    )
    RETURNING id INTO v_ms_id;

    FOR v_task IN SELECT value FROM jsonb_array_elements(v_ms->'tasks')
    LOOP
      INSERT INTO task (
        milestone_id,
        user_id,
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
