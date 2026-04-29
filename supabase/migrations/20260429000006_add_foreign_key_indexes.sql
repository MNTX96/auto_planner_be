-- PostgreSQL does not auto-index foreign key columns.
-- These indexes are required for RLS sub-selects and list queries to avoid sequential scans.

CREATE INDEX idx_plans_user_id        ON plans      (user_id);
CREATE INDEX idx_milestones_plan_id   ON milestones (plan_id);
CREATE INDEX idx_tasks_milestone_id   ON tasks      (milestone_id);

-- Composite indexes for ordered list queries
CREATE INDEX idx_milestones_plan_order ON milestones (plan_id, milestone_index);
CREATE INDEX idx_tasks_milestone_order ON tasks      (milestone_id, task_index);
