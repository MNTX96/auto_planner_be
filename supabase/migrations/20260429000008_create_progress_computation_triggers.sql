-- ============================================================
-- Trigger 1: Recalculate milestone progress when tasks change
-- Fires AFTER INSERT, UPDATE of status, or DELETE on tasks
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
  FROM tasks
  WHERE milestone_id = v_milestone_id;

  v_progress := CASE
    WHEN v_total = 0 THEN 0
    ELSE ROUND((v_completed::NUMERIC / v_total) * 100)
  END;

  UPDATE milestones
  SET progress_percentage = v_progress
  WHERE id = v_milestone_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER tasks_update_milestone_progress
  AFTER INSERT OR UPDATE OF status OR DELETE ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION recalculate_milestone_progress();

-- ============================================================
-- Trigger 2: Recalculate plan progress when milestone progress changes
-- Fires AFTER INSERT, UPDATE of progress_percentage, or DELETE on milestones
-- ============================================================
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
  FROM milestones
  WHERE plan_id = v_plan_id;

  UPDATE plans
  SET progress_percentage = v_progress
  WHERE id = v_plan_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER milestones_update_plan_progress
  AFTER INSERT OR UPDATE OF progress_percentage OR DELETE ON milestones
  FOR EACH ROW
  EXECUTE FUNCTION recalculate_plan_progress();
