-- Add reminders_json column to daily_task table.
-- This column stores multiple reminder offsets as a JSON array of integers
-- (minutes before the task start), complementing reminder_minutes_before.
ALTER TABLE daily_task
  ADD COLUMN IF NOT EXISTS reminders_json TEXT;
