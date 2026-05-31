-- Adds rich-text notes that can stand alone, be scheduled on the calendar,
-- or be attached to a plan, milestone, or task.

DO $$
BEGIN
  CREATE TYPE public.note_reference_type_enum AS ENUM (
    'plan',
    'milestone',
    'task'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

CREATE TABLE public.note (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  content_delta JSONB NOT NULL DEFAULT '[{"insert":"\n"}]'::jsonb,
  plain_text TEXT NOT NULL DEFAULT '',
  reference_type public.note_reference_type_enum,
  reference_id UUID,
  scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  deleted_by_device_id TEXT,
  CONSTRAINT note_reference_pair_check CHECK (
    (reference_type IS NULL AND reference_id IS NULL)
    OR (reference_type IS NOT NULL AND reference_id IS NOT NULL)
  ),
  CONSTRAINT note_content_delta_is_array CHECK (
    jsonb_typeof(content_delta) = 'array'
  )
);

COMMENT ON TABLE public.note IS
  'Stores user-owned rich-text notes using Quill Delta JSON.';
COMMENT ON COLUMN public.note.reference_type IS
  'Polymorphic reference target: plan, milestone, or task.';
COMMENT ON COLUMN public.note.reference_id IS
  'ID of the referenced plan, milestone, or task when reference_type is set.';
COMMENT ON COLUMN public.note.scheduled_at IS
  'Optional calendar timestamp for notes created from or shown on the calendar.';

CREATE TRIGGER note_set_updated_at
  BEFORE UPDATE ON public.note
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_note_user_id
  ON public.note(user_id);

CREATE INDEX idx_note_user_scheduled_at
  ON public.note(user_id, scheduled_at)
  WHERE scheduled_at IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_note_reference
  ON public.note(reference_type, reference_id)
  WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL
    AND deleted_at IS NULL;

CREATE INDEX idx_note_user_sync_changed
  ON public.note(user_id, updated_at, deleted_at);

ALTER TABLE public.note ENABLE ROW LEVEL SECURITY;

CREATE POLICY "note_select_own"
  ON public.note FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "note_insert_own"
  ON public.note FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "note_update_own"
  ON public.note FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "note_delete_own"
  ON public.note FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

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
    ),
    'note', COALESCE(
      (
        SELECT jsonb_agg(to_jsonb(n) ORDER BY n.updated_at, n.id)
        FROM public.note n
        WHERE n.user_id = v_user_id
          AND GREATEST(
            COALESCE(n.updated_at, n.created_at),
            COALESCE(n.deleted_at, '-infinity'::timestamptz)
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
