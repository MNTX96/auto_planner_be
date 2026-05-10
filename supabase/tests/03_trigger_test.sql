BEGIN;

SELECT plan(14);

-- Setup: user + plan + milestone + task
INSERT INTO auth.users (id, email) VALUES ('11111111-0000-0000-0000-000000000001', 'trigger_test@test.com');
INSERT INTO profile (id, email) VALUES ('11111111-0000-0000-0000-000000000001', 'trigger_test@test.com');

INSERT INTO plan (id, user_id, prompt_goal, title)
VALUES ('dddddddd-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'Goal', 'Plan');

INSERT INTO milestone (id, plan_id, name)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'M1');

INSERT INTO task (id, milestone_id, name) VALUES
  ('ffffffff-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 'Task 1'),
  ('ffffffff-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001', 'Task 2'),
  ('ffffffff-0000-0000-0000-000000000003', 'eeeeeeee-0000-0000-0000-000000000001', 'Task 3'),
  ('ffffffff-0000-0000-0000-000000000004', 'eeeeeeee-0000-0000-0000-000000000001', 'Task 4');

-- ============================================================
-- handle_new_user trigger: inserting to auth.users creates profile
-- ============================================================
INSERT INTO auth.users (id, email) VALUES ('22222222-0000-0000-0000-000000000001', 'new_user@test.com');
SELECT is(
  (SELECT COUNT(*) FROM profile WHERE id = '22222222-0000-0000-0000-000000000001')::INTEGER,
  1,
  'handle_new_user trigger creates profile on auth.users INSERT'
);

-- ============================================================
-- completed_at trigger: set when status → completed
-- ============================================================
UPDATE task SET status = 'completed' WHERE id = 'ffffffff-0000-0000-0000-000000000001';
SELECT isnt(
  (SELECT completed_at FROM task WHERE id = 'ffffffff-0000-0000-0000-000000000001'),
  NULL,
  'completed_at is set when task status becomes completed'
);

-- ============================================================
-- completed_at trigger: cleared when status reverts from completed
-- ============================================================
UPDATE task SET status = 'pending' WHERE id = 'ffffffff-0000-0000-0000-000000000001';
SELECT is(
  (SELECT completed_at FROM task WHERE id = 'ffffffff-0000-0000-0000-000000000001'),
  NULL,
  'completed_at is cleared when task reverts from completed'
);

-- ============================================================
-- Progress triggers: 0 of 4 completed → milestone = 0, plan = 0
-- ============================================================
SELECT is(
  (SELECT progress_percentage FROM milestone WHERE id = 'eeeeeeee-0000-0000-0000-000000000001'),
  0,
  'milestone progress = 0 when no tasks completed'
);
SELECT is(
  (SELECT progress_percentage FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  0,
  'plan progress = 0 when no tasks completed'
);

-- ============================================================
-- Progress triggers: 2 of 4 completed → milestone = 50, plan = 50
-- ============================================================
UPDATE task SET status = 'completed'
WHERE id IN ('ffffffff-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000002');

SELECT is(
  (SELECT progress_percentage FROM milestone WHERE id = 'eeeeeeee-0000-0000-0000-000000000001'),
  50,
  'milestone progress = 50 when 2 of 4 tasks completed'
);
SELECT is(
  (SELECT progress_percentage FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  50,
  'plan progress = 50 when only milestone is at 50%'
);

-- ============================================================
-- Progress triggers: 4 of 4 completed → milestone = 100, plan = 100
-- ============================================================
UPDATE task SET status = 'completed'
WHERE id IN ('ffffffff-0000-0000-0000-000000000003', 'ffffffff-0000-0000-0000-000000000004');

SELECT is(
  (SELECT progress_percentage FROM milestone WHERE id = 'eeeeeeee-0000-0000-0000-000000000001'),
  100,
  'milestone progress = 100 when all tasks completed'
);
SELECT is(
  (SELECT progress_percentage FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  100,
  'plan progress = 100 when only milestone is at 100%'
);

-- ============================================================
-- updated_at trigger: changes on UPDATE
-- ============================================================
DO $$ DECLARE orig TIMESTAMPTZ; BEGIN
  SELECT updated_at INTO orig FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001';
  PERFORM pg_sleep(0.01);
  UPDATE plan SET title = 'Updated Title' WHERE id = 'dddddddd-0000-0000-0000-000000000001';
END $$;

SELECT isnt(
  (SELECT updated_at FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  (SELECT created_at FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  'plan.updated_at changes after UPDATE'
);

-- ============================================================
-- Progress triggers: deleting a task recalculates progress
-- ============================================================
DELETE FROM task WHERE id = 'ffffffff-0000-0000-0000-000000000004';
-- 3 remaining tasks, all completed → still 100%
SELECT is(
  (SELECT progress_percentage FROM milestone WHERE id = 'eeeeeeee-0000-0000-0000-000000000001'),
  100,
  'milestone progress recalculates on task DELETE (3/3 completed = 100%)'
);

-- ============================================================
-- Progress triggers: milestone DELETE resets plan progress
-- ============================================================
DELETE FROM milestone WHERE id = 'eeeeeeee-0000-0000-0000-000000000001';
SELECT is(
  (SELECT progress_percentage FROM plan WHERE id = 'dddddddd-0000-0000-0000-000000000001'),
  0,
  'plan progress = 0 when all milestones deleted'
);

SELECT * FROM finish();

ROLLBACK;

