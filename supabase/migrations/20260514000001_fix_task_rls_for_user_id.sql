-- Fix task RLS policy to allow direct user_id check.
-- Previously, task_select_own only allowed access via milestone→plan join,
-- which blocked queries using task.user_id directly (including Realtime probes).
DROP POLICY IF EXISTS "task_select_own" ON task;
DROP POLICY IF EXISTS "task_insert_own" ON task;
DROP POLICY IF EXISTS "task_update_own" ON task;
DROP POLICY IF EXISTS "task_delete_own" ON task;

CREATE POLICY "task_select_own" ON task FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "task_insert_own" ON task FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "task_update_own" ON task FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "task_delete_own" ON task FOR DELETE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM milestone
      JOIN plan ON milestone.plan_id = plan.id
      WHERE task.milestone_id = milestone.id
        AND plan.user_id = (SELECT auth.uid())
    )
  );

-- Index to speed up the new direct user_id check
CREATE INDEX IF NOT EXISTS idx_task_user_id_rls ON task(user_id)
  WHERE user_id IS NOT NULL;
