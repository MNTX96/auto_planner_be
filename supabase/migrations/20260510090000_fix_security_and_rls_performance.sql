-- ============================================================
-- 1. DROP OLD RLS POLICIES
-- ============================================================
DROP POLICY IF EXISTS "profile_select_own" ON profile;
DROP POLICY IF EXISTS "profile_update_own" ON profile;

DROP POLICY IF EXISTS "plan_select_own" ON plan;
DROP POLICY IF EXISTS "plan_insert_own" ON plan;
DROP POLICY IF EXISTS "plan_update_own" ON plan;
DROP POLICY IF EXISTS "plan_delete_own" ON plan;

DROP POLICY IF EXISTS "milestone_select_own" ON milestone;
DROP POLICY IF EXISTS "milestone_insert_own" ON milestone;
DROP POLICY IF EXISTS "milestone_update_own" ON milestone;
DROP POLICY IF EXISTS "milestone_delete_own" ON milestone;

DROP POLICY IF EXISTS "task_select_own" ON task;
DROP POLICY IF EXISTS "task_insert_own" ON task;
DROP POLICY IF EXISTS "task_update_own" ON task;
DROP POLICY IF EXISTS "task_delete_own" ON task;


-- ============================================================
-- 2. CREATE OPTIMIZED RLS POLICIES (using (select auth.uid()))
-- ============================================================

-- profile
CREATE POLICY "profile_select_own" ON profile FOR SELECT TO authenticated USING ((SELECT auth.uid()) = id);
CREATE POLICY "profile_update_own" ON profile FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);

-- plan
CREATE POLICY "plan_select_own" ON plan FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "plan_insert_own" ON plan FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "plan_update_own" ON plan FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "plan_delete_own" ON plan FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- milestone
CREATE POLICY "milestone_select_own" ON milestone FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM plan WHERE plan.id = milestone.plan_id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "milestone_insert_own" ON milestone FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM plan WHERE plan.id = milestone.plan_id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "milestone_update_own" ON milestone FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM plan WHERE plan.id = milestone.plan_id AND plan.user_id = (SELECT auth.uid()))) WITH CHECK (EXISTS (SELECT 1 FROM plan WHERE plan.id = milestone.plan_id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "milestone_delete_own" ON milestone FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM plan WHERE plan.id = milestone.plan_id AND plan.user_id = (SELECT auth.uid())));

-- task
CREATE POLICY "task_select_own" ON task FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM milestone JOIN plan ON milestone.plan_id = plan.id WHERE task.milestone_id = milestone.id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "task_insert_own" ON task FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM milestone JOIN plan ON milestone.plan_id = plan.id WHERE task.milestone_id = milestone.id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "task_update_own" ON task FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM milestone JOIN plan ON milestone.plan_id = plan.id WHERE task.milestone_id = milestone.id AND plan.user_id = (SELECT auth.uid()))) WITH CHECK (EXISTS (SELECT 1 FROM milestone JOIN plan ON milestone.plan_id = plan.id WHERE task.milestone_id = milestone.id AND plan.user_id = (SELECT auth.uid())));
CREATE POLICY "task_delete_own" ON task FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM milestone JOIN plan ON milestone.plan_id = plan.id WHERE task.milestone_id = milestone.id AND plan.user_id = (SELECT auth.uid())));


-- ============================================================
-- 3. UPDATE RPC FUNCTION FOR SECURITY
-- ============================================================
CREATE OR REPLACE FUNCTION save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER -- Changed from SECURITY DEFINER to SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid()); -- Optimized performance here as well
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
    INSERT INTO milestone (plan_id, milestone_index, name, focus_objective)
    VALUES (
      v_plan_id,
      (v_ms->>'milestone_index')::INTEGER,
      v_ms->>'name',
      v_ms->>'focus_objective'
    )
    RETURNING id INTO v_ms_id;

    FOR v_task IN SELECT value FROM jsonb_array_elements(v_ms->'tasks')
    LOOP
      INSERT INTO task (
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

-- Restrict execution to authenticated users only
REVOKE EXECUTE ON FUNCTION save_plan_transaction(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_plan_transaction(JSONB) TO authenticated;
