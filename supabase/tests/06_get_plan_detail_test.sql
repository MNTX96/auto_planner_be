BEGIN;

SELECT plan(7);

-- Setup: two users + a plan owned by user A
INSERT INTO auth.users (id, email) VALUES
  ('00000000-1111-0000-0000-000000000001', 'user_a@get-plan-detail.test'),
  ('00000000-1111-0000-0000-000000000002', 'user_b@get-plan-detail.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO profile (id, email) VALUES
  ('00000000-1111-0000-0000-000000000001', 'user_a@get-plan-detail.test'),
  ('00000000-1111-0000-0000-000000000002', 'user_b@get-plan-detail.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO plan (id, user_id, prompt_goal, title)
VALUES ('aaaaaaaa-1111-0000-0000-000000000001',
        '00000000-1111-0000-0000-000000000001',
        'Goal A', 'Plan A');

INSERT INTO milestone (id, plan_id, milestone_index, name)
VALUES
  ('bbbbbbbb-1111-0000-0000-000000000001',
   'aaaaaaaa-1111-0000-0000-000000000001', 1, 'Milestone 1'),
  ('bbbbbbbb-1111-0000-0000-000000000002',
   'aaaaaaaa-1111-0000-0000-000000000001', 2, 'Milestone 2');

INSERT INTO daily_task (id, milestone_id, user_id, name, scheduled_start)
VALUES
  ('cccccccc-1111-0000-0000-000000000001',
   'bbbbbbbb-1111-0000-0000-000000000001',
   '00000000-1111-0000-0000-000000000001',
   'Task 1.1',
   '2026-01-01T09:00:00Z'),
  ('cccccccc-1111-0000-0000-000000000002',
   'bbbbbbbb-1111-0000-0000-000000000001',
   '00000000-1111-0000-0000-000000000001',
   'Task 1.2',
   '2026-01-01T10:00:00Z'),
  ('cccccccc-1111-0000-0000-000000000003',
   'bbbbbbbb-1111-0000-0000-000000000002',
   '00000000-1111-0000-0000-000000000001',
   'Task 2.1',
   '2026-01-02T09:00:00Z');

-- ============================================================
-- User A calls get_plan_detail for own plan
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-1111-0000-0000-000000000001"}';

SELECT is(
  (SELECT get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001')->'plan'->>'title'),
  'Plan A',
  'User A receives own plan'
);

SELECT is(
  (
    SELECT jsonb_array_length(
      get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001')->'milestones'
    )
  ),
  2,
  'Plan A has 2 milestones'
);

SELECT is(
  (
    SELECT jsonb_array_length(
      get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001')
        ->'milestones'->0->'tasks'
    )
  ),
  2,
  'Milestone 1 has 2 tasks'
);

SELECT is(
  (
    SELECT jsonb_array_length(
      get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001')
        ->'milestones'->1->'tasks'
    )
  ),
  1,
  'Milestone 2 has 1 task'
);

SELECT is(
  (
    SELECT (
      get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001')
        ->'milestones'->0->'tasks'->0
    ) ? 'details'
  ),
  false,
  'get_plan_detail task payload does not include removed details'
);

-- ============================================================
-- User B calls get_plan_detail for User A's plan → must fail
-- ============================================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-1111-0000-0000-000000000002"}';

SELECT throws_ok(
  $$ SELECT get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001') $$,
  'P0002',
  'Plan not found',
  'User B cannot read User A plan via RPC'
);

-- ============================================================
-- Anonymous call: RPC raises 'Not authenticated'
-- ============================================================
SET LOCAL role TO anon;
RESET request.jwt.claims;

SELECT throws_ok(
  $$ SELECT get_plan_detail('aaaaaaaa-1111-0000-0000-000000000001') $$,
  '42501',
  'Not authenticated',
  'Anonymous caller is rejected'
);

SELECT * FROM finish();

ROLLBACK;
