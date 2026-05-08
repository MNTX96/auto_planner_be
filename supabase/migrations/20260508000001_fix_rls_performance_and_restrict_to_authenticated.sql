-- Fix RLS performance warnings and restrict all policies to authenticated role.
--
-- Two changes per policy:
--   1. TO authenticated  — short-circuits anonymous requests at role level
--   2. (select auth.uid()) — evaluated once per query (InitPlan) instead of once per row

-- ============================================================
-- profiles
-- ============================================================
DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
CREATE POLICY "profiles_select_own"
  ON profiles FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

-- ============================================================
-- plans
-- ============================================================
DROP POLICY IF EXISTS "plans_all_own" ON plans;
CREATE POLICY "plans_all_own"
  ON plans FOR ALL
  TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ============================================================
-- milestones
-- ============================================================
DROP POLICY IF EXISTS "milestones_all_own" ON milestones;
CREATE POLICY "milestones_all_own"
  ON milestones FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM plans
      WHERE plans.id = milestones.plan_id
        AND plans.user_id = (select auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM plans
      WHERE plans.id = milestones.plan_id
        AND plans.user_id = (select auth.uid())
    )
  );

-- ============================================================
-- tasks
-- ============================================================
DROP POLICY IF EXISTS "tasks_all_own" ON tasks;
CREATE POLICY "tasks_all_own"
  ON tasks FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM milestones
      JOIN plans ON milestones.plan_id = plans.id
      WHERE tasks.milestone_id = milestones.id
        AND plans.user_id = (select auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM milestones
      JOIN plans ON milestones.plan_id = plans.id
      WHERE tasks.milestone_id = milestones.id
        AND plans.user_id = (select auth.uid())
    )
  );
