-- Ensure every task has an absolute start timestamp before enforcing the
-- constraint. Existing legacy rows may predate manual scheduling support.
UPDATE public.daily_task
SET scheduled_start = COALESCE(created_at, updated_at, now())
WHERE scheduled_start IS NULL;

ALTER TABLE public.daily_task
  ALTER COLUMN scheduled_start SET NOT NULL;
