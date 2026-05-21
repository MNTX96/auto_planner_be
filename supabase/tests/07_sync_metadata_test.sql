BEGIN;

SELECT plan(12);

-- Setup: two users so RLS can prove device cursors are isolated.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-2222-0000-0000-000000000001', 'user_a@sync.test'),
  ('00000000-2222-0000-0000-000000000002', 'user_b@sync.test');

INSERT INTO profile (id, email) VALUES
  ('00000000-2222-0000-0000-000000000001', 'user_a@sync.test'),
  ('00000000-2222-0000-0000-000000000002', 'user_b@sync.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO plan (id, user_id, prompt_goal, title)
VALUES (
  'aaaaaaaa-2222-0000-0000-000000000001',
  '00000000-2222-0000-0000-000000000001',
  'Sync goal',
  'Sync plan'
);

INSERT INTO milestone (id, plan_id, milestone_index, name)
VALUES (
  'bbbbbbbb-2222-0000-0000-000000000001',
  'aaaaaaaa-2222-0000-0000-000000000001',
  1,
  'Sync milestone'
);

INSERT INTO daily_task (id, milestone_id, user_id, name, scheduled_start)
VALUES (
  'cccccccc-2222-0000-0000-000000000001',
  'bbbbbbbb-2222-0000-0000-000000000001',
  '00000000-2222-0000-0000-000000000001',
  'Sync task',
  '2026-01-01T09:00:00Z'
);

SELECT has_table('public', 'user_device', 'user_device table exists');
SELECT has_column('public', 'user_device', 'device_id', 'user_device.device_id exists');
SELECT has_column('public', 'user_device', 'last_synced_at', 'user_device.last_synced_at exists');
SELECT has_column('public', 'plan', 'deleted_at', 'plan.deleted_at exists');
SELECT has_column('public', 'milestone', 'deleted_at', 'milestone.deleted_at exists');
SELECT has_column('public', 'daily_task', 'deleted_at', 'daily_task.deleted_at exists');

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-2222-0000-0000-000000000001"}';

SELECT is(
  (public.set_user_device_synced(
    'device-a',
    '2026-01-01T00:00:00Z'::timestamptz
  )).device_id,
  'device-a',
  'set_user_device_synced upserts the caller device'
);

SELECT is(
  (
    SELECT last_synced_at
    FROM public.user_device
    WHERE device_id = 'device-a'
  ),
  '2026-01-01T00:00:00Z'::timestamptz,
  'user_device stores the cursor timestamp'
);

SELECT is(
  jsonb_array_length(public.get_sync_changes(NULL)->'plan'),
  1,
  'get_sync_changes returns owned plans for a first sync'
);

SELECT is(
  jsonb_array_length(public.get_sync_changes(NULL)->'milestone'),
  1,
  'get_sync_changes returns owned milestones for a first sync'
);

SELECT is(
  jsonb_array_length(public.get_sync_changes(NULL)->'daily_task'),
  1,
  'get_sync_changes returns owned tasks for a first sync'
);

SET LOCAL request.jwt.claims TO '{"sub":"00000000-2222-0000-0000-000000000002"}';

SELECT is(
  (SELECT COUNT(*)::INTEGER FROM public.user_device WHERE device_id = 'device-a'),
  0,
  'another user cannot select a device cursor they do not own'
);

SELECT is(
  jsonb_array_length(public.get_sync_changes(NULL)->'plan'),
  0,
  'another user cannot pull rows they do not own'
);

SELECT * FROM finish();

ROLLBACK;
