-- 0. Clear all existing data to start fresh with the new schema constraints
TRUNCATE TABLE plan CASCADE;

-- 1. `plan` & `milestone` tables: Add `start_date` and `end_date`
ALTER TABLE plan 
ADD COLUMN start_date DATE,
ADD COLUMN end_date DATE;

ALTER TABLE milestone 
ADD COLUMN start_date DATE,
ADD COLUMN end_date DATE;

-- 2. `task` table changes

-- Drop old text-based task_time
ALTER TABLE task DROP COLUMN task_time;

-- Make `milestone_id` NULLABLE (to support standalone manual tasks)
ALTER TABLE task
ALTER COLUMN milestone_id DROP NOT NULL;

-- Add absolute time columns
ALTER TABLE task
ADD COLUMN scheduled_start TIMESTAMPTZ,
ADD COLUMN scheduled_end TIMESTAMPTZ;

-- Add user_id column to tasks table
ALTER TABLE task
ADD COLUMN user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Create an ENUM `task_type_enum`
CREATE TYPE task_type_enum AS ENUM ('ai_plan', 'manual_single', 'manual_routine');

-- Add `task_type` column (default 'ai_plan')
ALTER TABLE task
ADD COLUMN task_type task_type_enum NOT NULL DEFAULT 'ai_plan';

-- Add an `rrule` column to store RFC 5545 recurrence strings
ALTER TABLE task
ADD COLUMN rrule TEXT;

-- Add an index on `scheduled_start` for fast querying
CREATE INDEX idx_tasks_scheduled_start ON task(scheduled_start);
