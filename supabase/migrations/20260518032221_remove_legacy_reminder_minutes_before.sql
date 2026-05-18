-- Migrate the legacy single-reminder column into the multi-reminder JSON
-- column before removing it. reminders_json stores minute offsets as a JSON
-- array encoded in text, e.g. [0], [10], or [5,15].
UPDATE public.daily_task
SET reminders_json = jsonb_build_array(reminder_minutes_before)::text
WHERE reminder_minutes_before IS NOT NULL
  AND (reminders_json IS NULL OR btrim(reminders_json) = '');

ALTER TABLE public.daily_task
DROP COLUMN IF EXISTS reminder_minutes_before;

-- The singular-table migrations introduced replacement updated_at triggers
-- without removing the original plural-name triggers on plan/milestone.
DROP TRIGGER IF EXISTS plans_set_updated_at ON public.plan;
DROP TRIGGER IF EXISTS milestones_set_updated_at ON public.milestone;

-- These indexes are covered by existing composite unique indexes:
--   milestone(plan_id, milestone_index)
--   daily_task(milestone_id, task_index)
DROP INDEX IF EXISTS public.idx_milestones_plan_id;
DROP INDEX IF EXISTS public.idx_milestones_plan_order;
DROP INDEX IF EXISTS public.idx_tasks_milestone_id;
DROP INDEX IF EXISTS public.idx_tasks_milestone_order;
