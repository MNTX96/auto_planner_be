BEGIN;

SELECT plan(10);

-- Setup: create two test users and their profiles
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.com');

INSERT INTO profiles (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.com');

-- Create a plan owned by User A (bypass RLS for setup)
INSERT INTO plans (id, user_id, prompt_goal, title)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'Goal A', 'Plan A');

INSERT INTO milestones (id, plan_id, milestone_index, name)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        1, 'Milestone A1');

INSERT INTO tasks (id, milestone_id, task_index, name)
VALUES ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        1, 'Task A1');

-- ============================================================
-- Test as User B: should NOT see User A's data
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';

SELECT is(
  (SELECT COUNT(*) FROM plans WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A plan'
);

SELECT is(
  (SELECT COUNT(*) FROM milestones WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A milestone'
);

SELECT is(
  (SELECT COUNT(*) FROM tasks WHERE id = 'cccccccc-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A task'
);

SELECT throws_ok(
  $$ INSERT INTO plans (user_id, prompt_goal, title) VALUES
     ('00000000-0000-0000-0000-000000000001', 'Injected', 'Injected Plan') $$,
  'User B cannot INSERT plan for User A'
);

SELECT throws_ok(
  $$ UPDATE plans SET title = 'Hacked' WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'User B cannot UPDATE User A plan'
);

-- ============================================================
-- Test as User A: should see own data
-- ============================================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

SELECT is(
  (SELECT COUNT(*) FROM plans WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own plan'
);

SELECT is(
  (SELECT COUNT(*) FROM milestones WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own milestone'
);

SELECT is(
  (SELECT COUNT(*) FROM tasks WHERE id = 'cccccccc-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own task'
);

-- User A can update own plan
UPDATE plans SET title = 'Plan A Updated' WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT is(
  (SELECT title FROM plans WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Plan A Updated',
  'User A can UPDATE own plan'
);

-- ============================================================
-- profiles: no INSERT policy (only trigger creates rows)
-- ============================================================
SELECT policy_roles_are(
  'public', 'profiles', 'profiles_select_own', '{authenticated}',
  'profiles SELECT policy targets authenticated role'
);

SELECT * FROM finish();

ROLLBACK;
