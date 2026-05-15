-- ============================================================
-- 1. RENAME TABLE
-- ============================================================
ALTER TABLE task RENAME TO daily_task;

-- ============================================================
-- 2. DROP OLD TRIGGERS ON RENAMED TABLE
-- ============================================================
DROP TRIGGER IF EXISTS task_set_updated_at ON daily_task;
DROP TRIGGER IF EXISTS tasks_set_updated_at ON daily_task;
DROP TRIGGER IF EXISTS tasks_update_milestone_progress ON daily_task;
DROP TRIGGER IF EXISTS tasks_set_completed_at ON daily_task;
DROP TRIGGER IF EXISTS daily_task_set_updated_at ON daily_task;

-- ============================================================
-- 3. RECREATE TRIGGERS FOR daily_task
-- ============================================================
CREATE TRIGGER daily_task_set_updated_at
  BEFORE UPDATE ON daily_task
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER daily_task_set_completed_at
  BEFORE UPDATE OF status ON daily_task
  FOR EACH ROW EXECUTE FUNCTION set_task_completed_at();

CREATE TRIGGER daily_task_update_milestone_progress
  AFTER INSERT OR UPDATE OF status OR DELETE ON daily_task
  FOR EACH ROW EXECUTE FUNCTION recalculate_milestone_progress();

-- ============================================================
-- 4. UPDATE TRIGGER FUNCTIONS TO REFERENCE daily_task
-- ============================================================
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
  FROM daily_task
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

-- ============================================================
-- 5. DROP AND RECREATE RLS POLICIES FOR daily_task
-- ============================================================
DROP POLICY IF EXISTS "task_select_own" ON daily_task;
DROP POLICY IF EXISTS "task_insert_own" ON daily_task;
DROP POLICY IF EXISTS "task_update_own" ON daily_task;
DROP POLICY IF EXISTS "task_delete_own" ON daily_task;

CREATE POLICY "daily_task_select_own" ON daily_task FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE daily_task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "daily_task_insert_own" ON daily_task FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE daily_task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "daily_task_update_own" ON daily_task FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE daily_task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE daily_task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "daily_task_delete_own" ON daily_task FOR DELETE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE daily_task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

-- ============================================================
-- 6. RENAME INDEXES
-- ============================================================
ALTER INDEX IF EXISTS idx_tasks_scheduled_start RENAME TO idx_daily_task_scheduled_start;
ALTER INDEX IF EXISTS idx_task_user_id_rls RENAME TO idx_daily_task_user_id_rls;

-- ============================================================
-- 7. ADD COLUMNS: priority + calendar_event_id
--    Also ensure color and reminder_minutes_before exist (may
--    have been added via dashboard without a migration).
-- ============================================================
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high', 'critical');

ALTER TABLE daily_task
  ADD COLUMN priority         task_priority NOT NULL DEFAULT 'low',
  ADD COLUMN calendar_event_id TEXT;

-- Idempotent: add color / reminder if missing
ALTER TABLE daily_task
  ADD COLUMN IF NOT EXISTS color                  TEXT,
  ADD COLUMN IF NOT EXISTS reminder_minutes_before INTEGER;

-- ============================================================
-- 8. UPDATE save_plan_transaction RPC
-- ============================================================
CREATE OR REPLACE FUNCTION save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID := (SELECT auth.uid());
  v_plan_id    UUID;
  v_ms         JSONB;
  v_ms_index   INTEGER;
  v_task       JSONB;
  v_task_index INTEGER;
  v_ms_id      UUID;
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
      INSERT INTO daily_task (
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
        NULLIF(NULLIF(v_task->>'duration_minutes', '')::INTEGER, 0),
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
GRANT  EXECUTE ON FUNCTION save_plan_transaction(JSONB) TO authenticated;
