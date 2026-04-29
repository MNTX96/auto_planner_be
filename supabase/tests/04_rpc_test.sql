BEGIN;

SELECT plan(6);

-- Setup: authenticated user
INSERT INTO auth.users (id, email) VALUES ('33333333-0000-0000-0000-000000000001', 'rpc_test@test.com');
INSERT INTO profiles (id, email) VALUES ('33333333-0000-0000-0000-000000000001', 'rpc_test@test.com');

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"33333333-0000-0000-0000-000000000001"}';

-- ============================================================
-- Valid payload: inserts 1 plan, 2 milestones, 4 tasks
-- ============================================================
DO $$
DECLARE
  v_plan_id UUID;
  payload JSONB := '{
    "domain": "travel",
    "prompt_goal": "Trip to Da Nang",
    "title": "Da Nang 3 Days Plan",
    "milestones": [
      {
        "milestone_index": 1,
        "name": "Day 1",
        "focus_objective": "Arrival",
        "tasks": [
          {"task_index": 1, "name": "Check in hotel", "duration_minutes": 30},
          {"task_index": 2, "name": "Dinner at My Khe", "duration_minutes": 60}
        ]
      },
      {
        "milestone_index": 2,
        "name": "Day 2",
        "focus_objective": "Sightseeing",
        "tasks": [
          {"task_index": 1, "name": "Ba Na Hills", "duration_minutes": 240},
          {"task_index": 2, "name": "Dragon Bridge", "duration_minutes": 60}
        ]
      }
    ]
  }';
BEGIN
  v_plan_id := save_plan_transaction(payload);
  PERFORM set_config('test.plan_id', v_plan_id::TEXT, TRUE);
END $$;

SELECT isnt(
  current_setting('test.plan_id', TRUE)::UUID,
  NULL,
  'save_plan_transaction returns a non-null plan_id'
);

SELECT is(
  (SELECT COUNT(*) FROM plans WHERE id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  1,
  'save_plan_transaction inserts exactly 1 plan row'
);

SELECT is(
  (SELECT COUNT(*) FROM milestones WHERE plan_id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  2,
  'save_plan_transaction inserts 2 milestone rows'
);

SELECT is(
  (SELECT COUNT(*) FROM tasks t
   JOIN milestones m ON t.milestone_id = m.id
   WHERE m.plan_id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  4,
  'save_plan_transaction inserts 4 task rows'
);

-- ============================================================
-- Missing prompt_goal: must fail with NOT NULL violation
-- ============================================================
SELECT throws_ok(
  $$ SELECT save_plan_transaction('{"title":"T","milestones":[]}') $$,
  'save_plan_transaction fails when prompt_goal is missing'
);

-- ============================================================
-- Unauthenticated call: must raise "Not authenticated"
-- ============================================================
SET LOCAL role TO anon;
SELECT throws_ok(
  $$ SELECT save_plan_transaction('{"prompt_goal":"G","title":"T","milestones":[]}') $$,
  'P0001',
  'Not authenticated',
  'save_plan_transaction raises error when called unauthenticated'
);

SELECT * FROM finish();

ROLLBACK;
