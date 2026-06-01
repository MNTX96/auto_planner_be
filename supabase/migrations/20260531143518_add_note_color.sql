-- Adds an optional display color to notes, matching task color behavior.

ALTER TABLE public.note
  ADD COLUMN IF NOT EXISTS color TEXT;

COMMENT ON COLUMN public.note.color IS
  'Optional hex display color for note cards and calendar events.';
