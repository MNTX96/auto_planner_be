-- Dev-mode reset for incompatible y_crdt/wasm_run note CRDT payloads.
-- Preserve the AppFlowy document snapshot and plain text so notes still render.

DO $$
BEGIN
  IF to_regclass('public.note_crdt_update') IS NOT NULL THEN
    TRUNCATE TABLE public.note_crdt_update RESTART IDENTITY;
  END IF;
END $$;

ALTER TABLE public.note
  ADD COLUMN IF NOT EXISTS crdt_state_vector_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_update_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_version INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_crdt_server_seq BIGINT NOT NULL DEFAULT 0;

UPDATE public.note
SET crdt_state_vector_base64 = NULL,
    crdt_snapshot_update_base64 = NULL,
    crdt_snapshot_version = 0,
    last_crdt_server_seq = 0;

NOTIFY pgrst, 'reload schema';
