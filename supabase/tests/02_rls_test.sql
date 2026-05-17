BEGIN;

SELECT plan(10);

-- Setup: create two test users and their profiles
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.com');

INSERT INTO profile (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.com')
ON CONFLICT (id) DO NOTHING;

-- Create a plan owned by User A (bypass RLS for setup)
INSERT INTO plan (id, user_id, prompt_goal, title)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'Goal A', 'Plan A');

INSERT INTO milestone (id, plan_id, milestone_index, name)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001',
        1,
        'Milestone A1');

INSERT INTO daily_task (id, milestone_id, name)
VALUES ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'Task A1');

-- ============================================================
-- Test as User B: should NOT see User A's data
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';

SELECT is(
  (SELECT COUNT(*) FROM plan WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A plan'
);

SELECT is(
  (SELECT COUNT(*) FROM milestone WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A milestone'
);

SELECT is(
  (SELECT COUNT(*) FROM daily_task WHERE id = 'cccccccc-0000-0000-0000-000000000001')::INTEGER,
  0,
  'User B cannot SELECT User A daily_task'
);

SELECT throws_ok(
  $$ INSERT INTO plan (user_id, prompt_goal, title) VALUES
     ('00000000-0000-0000-0000-000000000001', 'Injected', 'Injected Plan') $$,
  '42501',
  'new row violates row-level security policy for table "plan"',
  'User B cannot INSERT plan for User A'
);

UPDATE plan SET title = 'Hacked'
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ============================================================
-- Test as User A: should see own data
-- ============================================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

SELECT is(
  (SELECT title FROM plan WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Plan A',
  'User B cannot UPDATE User A plan'
);

SELECT is(
  (SELECT COUNT(*) FROM plan WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own plan'
);

SELECT is(
  (SELECT COUNT(*) FROM milestone WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own milestone'
);

SELECT is(
  (SELECT COUNT(*) FROM daily_task WHERE id = 'cccccccc-0000-0000-0000-000000000001')::INTEGER,
  1,
  'User A can SELECT own daily_task'
);

-- User A can update own plan
UPDATE plan SET title = 'Plan A Updated' WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT is(
  (SELECT title FROM plan WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Plan A Updated',
  'User A can UPDATE own plan'
);

-- ============================================================
-- profile: no INSERT policy (only trigger creates rows)
-- ============================================================
SELECT policy_roles_are(
  'public', 'profile', 'profile_select_own', '{authenticated}',
  'profile SELECT policy targets authenticated role'
);

SELECT * FROM finish();

ROLLBACK;
