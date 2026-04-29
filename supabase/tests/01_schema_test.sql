BEGIN;

SELECT plan(30);

-- ============================================================
-- Tables exist
-- ============================================================
SELECT has_table('public', 'profiles',   'profiles table exists');
SELECT has_table('public', 'plans',      'plans table exists');
SELECT has_table('public', 'milestones', 'milestones table exists');
SELECT has_table('public', 'tasks',      'tasks table exists');

-- ============================================================
-- Columns exist on plans
-- ============================================================
SELECT has_column('public', 'plans', 'id',                    'plans.id exists');
SELECT has_column('public', 'plans', 'user_id',               'plans.user_id exists');
SELECT has_column('public', 'plans', 'prompt_goal',           'plans.prompt_goal exists');
SELECT has_column('public', 'plans', 'success_metrics',       'plans.success_metrics exists');
SELECT has_column('public', 'plans', 'expert_advice',         'plans.expert_advice exists');
SELECT has_column('public', 'plans', 'progress_percentage',   'plans.progress_percentage exists');
SELECT has_column('public', 'plans', 'updated_at',            'plans.updated_at exists');

-- ============================================================
-- Columns exist on milestones
-- ============================================================
SELECT has_column('public', 'milestones', 'updated_at', 'milestones.updated_at exists');
SELECT has_column('public', 'milestones', 'progress_percentage', 'milestones.progress_percentage exists');

-- ============================================================
-- Columns exist on tasks
-- ============================================================
SELECT has_column('public', 'tasks', 'completed_at', 'tasks.completed_at exists');
SELECT has_column('public', 'tasks', 'status',       'tasks.status exists');

-- ============================================================
-- ENUMs have correct values
-- ============================================================
SELECT has_type('public', 'plan_status', 'plan_status type exists');
SELECT has_type('public', 'task_status', 'task_status type exists');

-- ============================================================
-- Indexes exist
-- ============================================================
SELECT has_index('public', 'plans',      'idx_plans_user_id',        'index on plans(user_id) exists');
SELECT has_index('public', 'milestones', 'idx_milestones_plan_id',   'index on milestones(plan_id) exists');
SELECT has_index('public', 'tasks',      'idx_tasks_milestone_id',   'index on tasks(milestone_id) exists');

-- ============================================================
-- CHECK constraints: progress_percentage is bounded 0-100
-- ============================================================
SELECT col_has_check('public', 'plans',      'progress_percentage', 'plans.progress_percentage has CHECK constraint');
SELECT col_has_check('public', 'milestones', 'progress_percentage', 'milestones.progress_percentage has CHECK constraint');

-- ============================================================
-- UNIQUE constraints on ordering indexes
-- ============================================================
SELECT col_is_unique('public', 'milestones', ARRAY['plan_id', 'milestone_index'], 'milestones(plan_id, milestone_index) is unique');
SELECT col_is_unique('public', 'tasks',      ARRAY['milestone_id', 'task_index'],  'tasks(milestone_id, task_index) is unique');

-- ============================================================
-- NOT NULL constraints on key columns
-- ============================================================
SELECT col_not_null('public', 'plans',      'user_id',     'plans.user_id is NOT NULL');
SELECT col_not_null('public', 'plans',      'prompt_goal', 'plans.prompt_goal is NOT NULL');
SELECT col_not_null('public', 'milestones', 'plan_id',     'milestones.plan_id is NOT NULL');
SELECT col_not_null('public', 'tasks',      'milestone_id','tasks.milestone_id is NOT NULL');
SELECT col_not_null('public', 'tasks',      'name',        'tasks.name is NOT NULL');

SELECT * FROM finish();

ROLLBACK;
