-- Adds publish/draft state to notes. Draft notes sync between devices but are
-- hidden from calendar and normal note lists by client-side filters.

DO $$
BEGIN
  CREATE TYPE public.note_status_enum AS ENUM (
    'published',
    'draft'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

ALTER TABLE public.note
  ADD COLUMN IF NOT EXISTS status public.note_status_enum
    NOT NULL DEFAULT 'published';

COMMENT ON COLUMN public.note.status IS
  'Publication state for notes. Draft notes are user-owned synced drafts and are hidden from calendar views.';

DROP INDEX IF EXISTS public.idx_note_user_scheduled_at;
CREATE INDEX IF NOT EXISTS idx_note_user_scheduled_at
  ON public.note(user_id, scheduled_at)
  WHERE scheduled_at IS NOT NULL
    AND deleted_at IS NULL
    AND status = 'published';

DROP INDEX IF EXISTS public.idx_note_reference;
CREATE INDEX IF NOT EXISTS idx_note_reference
  ON public.note(reference_type, reference_id)
  WHERE reference_type IS NOT NULL
    AND reference_id IS NOT NULL
    AND deleted_at IS NULL
    AND status = 'published';

CREATE INDEX IF NOT EXISTS idx_note_user_status_updated
  ON public.note(user_id, status, updated_at)
  WHERE deleted_at IS NULL;
