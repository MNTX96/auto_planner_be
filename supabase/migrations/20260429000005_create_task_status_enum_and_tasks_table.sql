CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'missed');

-- Stores individual actionable tasks within a milestone (AI Tier 3)
CREATE TABLE tasks (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  milestone_id          UUID        NOT NULL REFERENCES milestones(id) ON DELETE CASCADE,
  task_index            INTEGER     NOT NULL,

  -- AI-generated task data
  task_time             TEXT,
  name                  TEXT        NOT NULL,
  duration_minutes      INTEGER     CHECK (duration_minutes > 0),
  resources_or_location TEXT,
  details               TEXT,

  status                task_status NOT NULL DEFAULT 'pending',
  completed_at          TIMESTAMPTZ,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (milestone_id, task_index)
);

CREATE TRIGGER tasks_set_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();
