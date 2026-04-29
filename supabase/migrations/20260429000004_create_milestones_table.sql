-- Stores phases / days within a plan (AI Tier 2)
CREATE TABLE milestones (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id             UUID        NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  milestone_index     INTEGER     NOT NULL,
  name                TEXT        NOT NULL,
  focus_objective     TEXT,
  progress_percentage INTEGER     NOT NULL DEFAULT 0 CHECK (progress_percentage BETWEEN 0 AND 100),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (plan_id, milestone_index)
);

CREATE TRIGGER milestones_set_updated_at
  BEFORE UPDATE ON milestones
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();
