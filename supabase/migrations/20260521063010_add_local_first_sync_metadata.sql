-- Adds the metadata needed for local-first multi-device sync.
--
-- Each installed app instance owns one user_device row. The cursor is only
-- advanced after a successful full sync cycle, so missed realtime events can
-- be recovered by a later pull.

CREATE TABLE public.user_device (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  last_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_device_device_id_not_blank
    CHECK (length(trim(device_id)) > 0),
  CONSTRAINT user_device_user_device_unique
    UNIQUE (user_id, device_id)
);

COMMENT ON TABLE public.user_device IS
  'Stores one sync cursor per authenticated user and app device.';
COMMENT ON COLUMN public.user_device.device_id IS
  'App-generated UUID persisted locally on the device.';
COMMENT ON COLUMN public.user_device.last_synced_at IS
  'Last successful full local-first sync cursor for this device.';

CREATE TRIGGER user_device_set_updated_at
  BEFORE UPDATE ON public.user_device
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.user_device ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_device_select_own"
  ON public.user_device FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "user_device_insert_own"
  ON public.user_device FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "user_device_update_own"
  ON public.user_device FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "user_device_delete_own"
  ON public.user_device FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE INDEX idx_user_device_user_id
  ON public.user_device(user_id);

ALTER TABLE public.plan
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by_device_id TEXT;

ALTER TABLE public.milestone
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by_device_id TEXT;

ALTER TABLE public.daily_task
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by_device_id TEXT;

CREATE INDEX IF NOT EXISTS idx_plan_user_sync_changed
  ON public.plan(user_id, updated_at, deleted_at);

CREATE INDEX IF NOT EXISTS idx_milestone_sync_changed
  ON public.milestone(plan_id, updated_at, deleted_at);

CREATE INDEX IF NOT EXISTS idx_daily_task_user_sync_changed
  ON public.daily_task(user_id, updated_at, deleted_at)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_daily_task_deleted_at
  ON public.daily_task(deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_sync_changes(
  p_last_synced_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_since TIMESTAMPTZ := COALESCE(p_last_synced_at, '-infinity'::timestamptz);
  v_server_synced_at TIMESTAMPTZ := NOW();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'server_synced_at', v_server_synced_at,
    'plan', COALESCE(
      (
        SELECT jsonb_agg(to_jsonb(p) ORDER BY p.updated_at, p.id)
        FROM public.plan p
        WHERE p.user_id = v_user_id
          AND GREATEST(
            p.updated_at,
            COALESCE(p.deleted_at, '-infinity'::timestamptz)
          ) > v_since
      ),
      '[]'::jsonb
    ),
    'milestone', COALESCE(
      (
        SELECT jsonb_agg(to_jsonb(m) ORDER BY m.updated_at, m.id)
        FROM public.milestone m
        JOIN public.plan p ON p.id = m.plan_id
        WHERE p.user_id = v_user_id
          AND GREATEST(
            COALESCE(m.updated_at, m.created_at),
            COALESCE(m.deleted_at, '-infinity'::timestamptz)
          ) > v_since
      ),
      '[]'::jsonb
    ),
    'daily_task', COALESCE(
      (
        SELECT jsonb_agg(to_jsonb(t) ORDER BY t.updated_at, t.id)
        FROM public.daily_task t
        LEFT JOIN public.milestone m ON m.id = t.milestone_id
        LEFT JOIN public.plan p ON p.id = m.plan_id
        WHERE (
            t.user_id = v_user_id
            OR p.user_id = v_user_id
          )
          AND GREATEST(
            COALESCE(t.updated_at, t.created_at),
            COALESCE(t.deleted_at, '-infinity'::timestamptz)
          ) > v_since
      ),
      '[]'::jsonb
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_sync_changes(TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sync_changes(TIMESTAMPTZ)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_user_device_synced(
  p_device_id TEXT,
  p_last_synced_at TIMESTAMPTZ
)
RETURNS public.user_device
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_device public.user_device;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_device_id IS NULL OR length(trim(p_device_id)) = 0 THEN
    RAISE EXCEPTION 'device_id is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.user_device (
    user_id,
    device_id,
    last_synced_at
  ) VALUES (
    v_user_id,
    p_device_id,
    p_last_synced_at
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    last_synced_at = EXCLUDED.last_synced_at
  RETURNING * INTO v_device;

  RETURN v_device;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_user_device_synced(TEXT, TIMESTAMPTZ)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_device_synced(TEXT, TIMESTAMPTZ)
  TO authenticated;
