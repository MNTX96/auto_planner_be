-- Ensures AppFlowy note columns exist on environments where Edge Functions
-- were deployed before PostgREST saw the note schema migration.

CREATE OR REPLACE FUNCTION public.appflowy_document_from_plain_text(p_text TEXT)
RETURNS JSONB
LANGUAGE sql
VOLATILE
SET search_path = public
AS $$
  WITH lines AS (
    SELECT line, ordinality
    FROM regexp_split_to_table(COALESCE(p_text, ''), E'\n')
      WITH ORDINALITY AS split(line, ordinality)
  )
  SELECT jsonb_build_object(
    'document',
    jsonb_build_object(
      'type',
      'page',
      'data',
      jsonb_build_object('_note_block_id', 'root'),
      'children',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'type',
              'paragraph',
              'data',
              jsonb_build_object(
                '_note_block_id',
                gen_random_uuid()::TEXT,
                'delta',
                jsonb_build_array(jsonb_build_object('insert', line))
              )
            )
            ORDER BY ordinality
          )
          FROM lines
        ),
        '[]'::jsonb
      )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.normalize_note_content_document(
  p_document JSONB,
  p_fallback_text TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
VOLATILE
SET search_path = public
AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_document) = 'object' AND p_document ? 'document'
      THEN p_document
    WHEN jsonb_typeof(p_document) = 'string'
      THEN public.appflowy_document_from_plain_text(p_document#>>'{}')
    ELSE public.appflowy_document_from_plain_text(COALESCE(p_fallback_text, ''))
  END;
$$;

CREATE OR REPLACE FUNCTION public.plain_text_from_appflowy_document(
  p_document JSONB
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT btrim(
    COALESCE(
      (
        SELECT string_agg(block_text, E'\n' ORDER BY block_ordinality)
        FROM (
          SELECT
            block_ordinality,
            COALESCE(
              (
                SELECT string_agg(op->>'insert', '' ORDER BY op_ordinality)
                FROM jsonb_array_elements(
                  COALESCE(block->'data'->'delta', '[]'::jsonb)
                ) WITH ORDINALITY AS delta_ops(op, op_ordinality)
                WHERE jsonb_typeof(op->'insert') = 'string'
              ),
              ''
            ) AS block_text
          FROM jsonb_array_elements(
            COALESCE(p_document#>'{document,children}', '[]'::jsonb)
          ) WITH ORDINALITY AS blocks(block, block_ordinality)
        ) block_texts
      ),
      ''
    ),
    E'\n'
  );
$$;

ALTER TABLE public.note
  DROP CONSTRAINT IF EXISTS note_content_delta_is_array,
  DROP COLUMN IF EXISTS status,
  DROP COLUMN IF EXISTS content_delta,
  ADD COLUMN IF NOT EXISTS content_document JSONB,
  ADD COLUMN IF NOT EXISTS crdt_state_vector_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_update_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_version BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_crdt_server_seq BIGINT NOT NULL DEFAULT 0;

UPDATE public.note
SET content_document = public.normalize_note_content_document(
  content_document,
  plain_text
)
WHERE content_document IS NULL
  OR jsonb_typeof(content_document) <> 'object'
  OR NOT (content_document ? 'document');

ALTER TABLE public.note
  ALTER COLUMN content_document SET DEFAULT public.appflowy_document_from_plain_text(''),
  ALTER COLUMN content_document SET NOT NULL,
  DROP CONSTRAINT IF EXISTS note_content_document_is_object,
  ADD CONSTRAINT note_content_document_is_object CHECK (
    jsonb_typeof(content_document) = 'object'
    AND content_document ? 'document'
  );

UPDATE public.note
SET
  crdt_snapshot_version = COALESCE(crdt_snapshot_version, 0),
  last_crdt_server_seq = COALESCE(last_crdt_server_seq, 0);

ALTER TABLE public.note
  ALTER COLUMN crdt_snapshot_version SET DEFAULT 0,
  ALTER COLUMN crdt_snapshot_version SET NOT NULL,
  ALTER COLUMN last_crdt_server_seq SET DEFAULT 0,
  ALTER COLUMN last_crdt_server_seq SET NOT NULL;

COMMENT ON TABLE public.note IS
  'Stores AppFlowy block document snapshots for local-first notes.';
COMMENT ON COLUMN public.note.content_document IS
  'AppFlowy Editor document JSON snapshot used for render, search, and previews.';
COMMENT ON COLUMN public.note.crdt_state_vector_base64 IS
  'Base64-encoded Yjs/y_crdt state vector for the latest local snapshot.';
COMMENT ON COLUMN public.note.crdt_snapshot_update_base64 IS
  'Base64-encoded full Yjs/y_crdt document update used to hydrate the latest snapshot.';
COMMENT ON COLUMN public.note.crdt_snapshot_version IS
  'Monotonic snapshot version incremented by local note saves.';
COMMENT ON COLUMN public.note.last_crdt_server_seq IS
  'Last CRDT update server sequence applied to this note snapshot.';

DROP FUNCTION IF EXISTS public.append_plain_text_to_quill_delta(JSONB, TEXT);
DROP FUNCTION IF EXISTS public.plain_text_from_quill_delta(JSONB);
DROP FUNCTION IF EXISTS public.normalize_note_content_delta(JSONB, TEXT);
DROP FUNCTION IF EXISTS public.quill_delta_from_plain_text(TEXT);

DROP INDEX IF EXISTS public.idx_note_user_status_updated;
CREATE INDEX IF NOT EXISTS idx_note_user_scheduled_at
  ON public.note(user_id, scheduled_at)
  WHERE scheduled_at IS NOT NULL
    AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_note_reference
  ON public.note(reference_type, reference_id)
  WHERE reference_type IS NOT NULL
    AND reference_id IS NOT NULL
    AND deleted_at IS NULL;

DROP TYPE IF EXISTS public.note_status_enum;

CREATE TABLE IF NOT EXISTS public.note_crdt_update (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id UUID NOT NULL REFERENCES public.note(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  client_seq BIGINT NOT NULL,
  server_seq BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE,
  update_base64 TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(note_id, device_id, client_seq)
);

CREATE INDEX IF NOT EXISTS idx_note_crdt_update_note_server_seq
  ON public.note_crdt_update(note_id, server_seq);

ALTER TABLE public.note_crdt_update ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "note_crdt_update_select_own"
  ON public.note_crdt_update;
CREATE POLICY "note_crdt_update_select_own"
  ON public.note_crdt_update FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.note n
      WHERE n.id = note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "note_crdt_update_insert_own"
  ON public.note_crdt_update;
CREATE POLICY "note_crdt_update_insert_own"
  ON public.note_crdt_update FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.note n
      WHERE n.id = note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

NOTIFY pgrst, 'reload schema';
