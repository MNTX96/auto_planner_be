BEGIN;

SELECT plan(8);

-- Setup: authenticated user
INSERT INTO auth.users (id, email) VALUES ('33333333-0000-0000-0000-000000000001', 'rpc_test@test.com');
INSERT INTO profile (id, email) VALUES ('33333333-0000-0000-0000-000000000001', 'rpc_test@test.com');

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"33333333-0000-0000-0000-000000000001"}';

-- ============================================================
-- Valid payload: inserts 1 plan, 2 milestones, 4 tasks
-- ============================================================
DO $$
DECLARE
  v_plan_id UUID;
  payload JSONB := '{
    "domain": "Travel",
    "prompt_goal": "Trip to Da Nang",
    "title": "Da Nang 3 Days Plan",
    "start_date": "2026-05-10",
    "end_date": "2026-05-12",
    "milestones": [
      {
        "name": "Day 1",
        "start_date": "2026-05-10",
        "end_date": "2026-05-10",
        "tasks": [
          {"name": "Check in hotel", "scheduled_start": "2026-05-10T14:00:00Z", "scheduled_end": "2026-05-10T14:30:00Z", "duration_minutes": 30},
          {"name": "Dinner at My Khe", "scheduled_start": "2026-05-10T18:00:00Z", "scheduled_end": "2026-05-10T19:00:00Z", "duration_minutes": 60}
        ]
      },
      {
        "name": "Day 2",
        "start_date": "2026-05-11",
        "end_date": "2026-05-11",
        "tasks": [
          {"name": "Ba Na Hills", "scheduled_start": "2026-05-11T08:00:00Z", "scheduled_end": "2026-05-11T12:00:00Z", "duration_minutes": 240},
          {"name": "Dragon Bridge", "scheduled_start": "2026-05-11T20:00:00Z", "scheduled_end": "2026-05-11T21:00:00Z", "duration_minutes": 60}
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
  (SELECT COUNT(*) FROM plan WHERE id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  1,
  'save_plan_transaction inserts exactly 1 plan row'
);

SELECT is(
  (SELECT COUNT(*) FROM milestone WHERE plan_id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  2,
  'save_plan_transaction inserts 2 milestone rows'
);

SELECT is(
  (SELECT COUNT(*) FROM task t
   JOIN milestone m ON t.milestone_id = m.id
   WHERE m.plan_id = current_setting('test.plan_id', TRUE)::UUID)::INTEGER,
  4,
  'save_plan_transaction inserts 4 task rows'
);

SELECT is(
  (
    SELECT string_agg(milestone_index::TEXT, ',' ORDER BY milestone_index)
    FROM milestone
    WHERE plan_id = current_setting('test.plan_id', TRUE)::UUID
  ),
  '1,2',
  'save_plan_transaction fills missing milestone indexes by order'
);

SELECT is(
  (
    SELECT string_agg(task_indexes, ';' ORDER BY milestone_index)
    FROM (
      SELECT
        m.milestone_index,
        string_agg(t.task_index::TEXT, ',' ORDER BY t.task_index) AS task_indexes
      FROM milestone m
      JOIN task t ON t.milestone_id = m.id
      WHERE m.plan_id = current_setting('test.plan_id', TRUE)::UUID
      GROUP BY m.milestone_index
    ) indexed_tasks
  ),
  '1,2;1,2',
  'save_plan_transaction fills missing task indexes by order'
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
