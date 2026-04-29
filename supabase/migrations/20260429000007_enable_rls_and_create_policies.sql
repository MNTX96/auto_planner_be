-- ============================================================
-- profiles
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "profiles_select_own"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

-- Users can update their own profile (INSERT is handled by the trigger only)
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ============================================================
-- plans
-- ============================================================
ALTER TABLE plans ENABLE ROW LEVEL SECURITY;

-- Users can fully manage their own plans
-- WITH CHECK on writes prevents inserting a plan for another user_id
CREATE POLICY "plans_all_own"
  ON plans FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- milestones
-- ============================================================
ALTER TABLE milestones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "milestones_all_own"
  ON milestones FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM plans
      WHERE plans.id = milestones.plan_id
        AND plans.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM plans
      WHERE plans.id = milestones.plan_id
        AND plans.user_id = auth.uid()
    )
  );

-- ============================================================
-- tasks
-- ============================================================
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tasks_all_own"
  ON tasks FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM milestones
      JOIN plans ON milestones.plan_id = plans.id
      WHERE tasks.milestone_id = milestones.id
        AND plans.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM milestones
      JOIN plans ON milestones.plan_id = plans.id
      WHERE tasks.milestone_id = milestones.id
        AND plans.user_id = auth.uid()
    )
  );
