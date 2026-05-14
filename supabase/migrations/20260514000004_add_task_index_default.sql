-- PostgreSQL validates NOT NULL before ON CONFLICT resolution.
-- Even if a row already exists (UPDATE path), the INSERT attempt fails first
-- if task_index has no default. Adding DEFAULT 0 fixes upserts that omit task_index.
ALTER TABLE task
  ALTER COLUMN task_index SET DEFAULT 0;
