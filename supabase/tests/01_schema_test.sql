BEGIN;

SELECT plan(51);

-- ============================================================
-- Tables exist
-- ============================================================
SELECT has_table('public', 'profile',   'profile table exists');
SELECT has_table('public', 'plan',      'plan table exists');
SELECT has_table('public', 'milestone', 'milestone table exists');
SELECT has_table('public', 'daily_task', 'daily_task table exists');
SELECT has_table('public', 'note', 'note table exists');

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
-- Columns exist on daily_task
-- ============================================================
SELECT has_column('public', 'daily_task', 'completed_at', 'daily_task.completed_at exists');
SELECT has_column('public', 'daily_task', 'status',       'daily_task.status exists');
SELECT has_column('public', 'daily_task', 'scheduled_start', 'daily_task.scheduled_start exists');
SELECT has_column('public', 'daily_task', 'reminders_json', 'daily_task.reminders_json exists');
SELECT hasnt_column('public', 'daily_task', 'reminder_minutes_before', 'daily_task.reminder_minutes_before removed');

-- ============================================================
-- Columns exist on note
-- ============================================================
SELECT has_column('public', 'note', 'id', 'note.id exists');
SELECT has_column('public', 'note', 'user_id', 'note.user_id exists');
SELECT has_column('public', 'note', 'title', 'note.title exists');
SELECT has_column('public', 'note', 'content_delta', 'note.content_delta exists');
SELECT has_column('public', 'note', 'plain_text', 'note.plain_text exists');
SELECT has_column('public', 'note', 'color', 'note.color exists');
SELECT has_column('public', 'note', 'reference_type', 'note.reference_type exists');
SELECT has_column('public', 'note', 'reference_id', 'note.reference_id exists');
SELECT has_column('public', 'note', 'scheduled_at', 'note.scheduled_at exists');
SELECT has_column('public', 'note', 'updated_at', 'note.updated_at exists');
SELECT has_column('public', 'note', 'deleted_at', 'note.deleted_at exists');

-- ============================================================
-- ENUMs have correct values
-- ============================================================
SELECT has_type('public', 'plan_status', 'plan_status type exists');
SELECT has_type('public', 'task_status', 'task_status type exists');
SELECT has_type('public', 'note_reference_type_enum', 'note_reference_type_enum type exists');
SELECT ok(
  'reminder' = ANY (
    ARRAY(SELECT unnest(enum_range(NULL::public.task_type_enum))::text)
  ),
  'task_type_enum includes reminder'
);

-- ============================================================
-- Indexes exist
-- ============================================================
SELECT has_index('public', 'plan',      'idx_plans_user_id',        'index on plan(user_id) exists');
SELECT has_index('public', 'daily_task', 'idx_daily_task_scheduled_start', 'index on daily_task(scheduled_start) exists');
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_milestones_plan_id'
  ),
  0,
  'redundant idx_milestones_plan_id removed'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_milestones_plan_order'
  ),
  0,
  'redundant idx_milestones_plan_order removed'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_tasks_milestone_id'
  ),
  0,
  'redundant idx_tasks_milestone_id removed'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_tasks_milestone_order'
  ),
  0,
  'redundant idx_tasks_milestone_order removed'
);

-- ============================================================
-- Trigger cleanup
-- ============================================================
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_trigger
    JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_class.relname = 'plan'
      AND pg_trigger.tgname = 'plan_set_updated_at'
      AND NOT pg_trigger.tgisinternal
  ),
  1,
  'plan keeps exactly one updated_at trigger'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_trigger
    JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_class.relname = 'plan'
      AND pg_trigger.tgname = 'plans_set_updated_at'
      AND NOT pg_trigger.tgisinternal
  ),
  0,
  'duplicate plans_set_updated_at trigger removed'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_trigger
    JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_class.relname = 'milestone'
      AND pg_trigger.tgname = 'milestone_set_updated_at'
      AND NOT pg_trigger.tgisinternal
  ),
  1,
  'milestone keeps exactly one updated_at trigger'
);
SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_trigger
    JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_class.relname = 'milestone'
      AND pg_trigger.tgname = 'milestones_set_updated_at'
      AND NOT pg_trigger.tgisinternal
  ),
  0,
  'duplicate milestones_set_updated_at trigger removed'
);

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
-- SELECT col_is_unique('public', 'daily_task', ARRAY['milestone_id', 'task_index'], 'daily_task(milestone_id, task_index) is unique');

-- ============================================================
-- NOT NULL constraints on key columns
-- ============================================================
SELECT col_not_null('public', 'plan',      'user_id',     'plan.user_id is NOT NULL');
SELECT col_not_null('public', 'plan',      'prompt_goal', 'plan.prompt_goal is NOT NULL');
SELECT col_not_null('public', 'milestone', 'plan_id',     'milestone.plan_id is NOT NULL');
SELECT col_not_null('public', 'daily_task', 'name', 'daily_task.name is NOT NULL');
SELECT col_not_null('public', 'daily_task', 'scheduled_start', 'daily_task.scheduled_start is NOT NULL');

SELECT * FROM finish();

ROLLBACK;
