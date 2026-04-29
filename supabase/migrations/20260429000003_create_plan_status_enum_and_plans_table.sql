CREATE TYPE plan_status AS ENUM ('active', 'completed', 'abandoned');

CREATE TABLE plans (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  domain                TEXT,

  -- Original user inputs — preserved for AI re-generation
  prompt_goal           TEXT        NOT NULL,
  prompt_current_status TEXT,
  prompt_available_time TEXT,
  prompt_constraints    TEXT,

  -- AI-generated overview (Tier 1)
  title                 TEXT        NOT NULL,
  ultimate_goal         TEXT,
  total_duration        TEXT,

  -- AI-generated arrays stored as JSONB — read-only, no per-item interaction
  success_metrics       JSONB       NOT NULL DEFAULT '[]'::jsonb,
  expert_advice         JSONB       NOT NULL DEFAULT '{}'::jsonb,

  status                plan_status NOT NULL DEFAULT 'active',
  progress_percentage   INTEGER     NOT NULL DEFAULT 0 CHECK (progress_percentage BETWEEN 0 AND 100),

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER plans_set_updated_at
  BEFORE UPDATE ON plans
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();
