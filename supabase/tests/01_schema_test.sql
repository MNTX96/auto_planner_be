BEGIN;

SELECT plan(30);

-- ============================================================
-- Tables exist
-- ============================================================
SELECT has_table('public', 'profile',   'profile table exists');
SELECT has_table('public', 'plan',      'plan table exists');
SELECT has_table('public', 'milestone', 'milestone table exists');
SELECT has_table('public', 'task',      'task table exists');

-- ============================================================
-- Columns exist on plan
-- ============================================================
SELECT has_column('public', 'plan', 'id',                    'plan.id exists');
SELECT has_column('public', 'plan', 'user_id',               'plan.user_id exists');
SELECT has_column('public', 'plan', 'prompt_goal',           'plan.prompt_goal exists');
SELECT has_column('public', 'plan', 'success_metrics',       'plan.success_metrics exists');
SELECT has_column('public', 'plan', 'expert_advice',         'plan.expert_advice exists');
SELECT has_column('public', 'plan', 'progress_percentage',   'plan.progress_percentage exists');
SELECT has_column('public', 'plan', 'updated_at',            'plan.updated_at exists');

-- ============================================================
-- Columns exist on milestone
-- ============================================================
SELECT has_column('public', 'milestone', 'updated_at', 'milestone.updated_at exists');
SELECT has_column('public', 'milestone', 'progress_percentage', 'milestone.progress_percentage exists');

-- ============================================================
-- Columns exist on task
-- ============================================================
SELECT has_column('public', 'task', 'completed_at', 'task.completed_at exists');
SELECT has_column('public', 'task', 'status',       'task.status exists');
SELECT has_column('public', 'task', 'scheduled_start', 'task.scheduled_start exists');

-- ============================================================
-- ENUMs have correct values
-- ============================================================
SELECT has_type('public', 'plan_status', 'plan_status type exists');
SELECT has_type('public', 'task_status', 'task_status type exists');

-- ============================================================
-- Indexes exist
-- ============================================================
SELECT has_index('public', 'plan',      'idx_plans_user_id',        'index on plan(user_id) exists');
SELECT has_index('public', 'milestone', 'idx_milestones_plan_id',   'index on milestone(plan_id) exists');
SELECT has_index('public', 'task',      'idx_tasks_milestone_id',   'index on task(milestone_id) exists');

-- ============================================================
-- CHECK constraints: progress_percentage is bounded 0-100
-- ============================================================
SELECT col_has_check('public', 'plan',      'progress_percentage', 'plan.progress_percentage has CHECK constraint');
SELECT col_has_check('public', 'milestone', 'progress_percentage', 'milestone.progress_percentage has CHECK constraint');

-- ============================================================
-- UNIQUE constraints on ordering indexes
-- ============================================================
-- Note: milestone_index and task_index were removed in favor of absolute time
-- SELECT col_is_unique('public', 'milestone', ARRAY['plan_id', 'milestone_index'], 'milestone(plan_id, milestone_index) is unique');
-- SELECT col_is_unique('public', 'task',      ARRAY['milestone_id', 'task_index'],  'task(milestone_id, task_index) is unique');

-- ============================================================
-- NOT NULL constraints on key columns
-- ============================================================
SELECT col_not_null('public', 'plan',      'user_id',     'plan.user_id is NOT NULL');
SELECT col_not_null('public', 'plan',      'prompt_goal', 'plan.prompt_goal is NOT NULL');
SELECT col_not_null('public', 'milestone', 'plan_id',     'milestone.plan_id is NOT NULL');
SELECT col_not_null('public', 'task',      'name',        'task.name is NOT NULL');

SELECT * FROM finish();

ROLLBACK;

