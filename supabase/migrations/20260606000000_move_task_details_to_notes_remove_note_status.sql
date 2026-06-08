-- Dev-mode destructive reset for AppFlowy Editor notes and CRDT sync.

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

DROP FUNCTION IF EXISTS public.append_plain_text_to_quill_delta(JSONB, TEXT);
DROP FUNCTION IF EXISTS public.plain_text_from_quill_delta(JSONB);
DROP FUNCTION IF EXISTS public.normalize_note_content_delta(JSONB, TEXT);
DROP FUNCTION IF EXISTS public.quill_delta_from_plain_text(TEXT);

DROP TABLE IF EXISTS public.note_crdt_update;

TRUNCATE TABLE public.note RESTART IDENTITY CASCADE;

DROP INDEX IF EXISTS public.idx_note_user_status_updated;
DROP INDEX IF EXISTS public.idx_note_user_scheduled_at;
DROP INDEX IF EXISTS public.idx_note_reference;

ALTER TABLE public.note
  DROP CONSTRAINT IF EXISTS note_content_delta_is_array,
  DROP COLUMN IF EXISTS status,
  DROP COLUMN IF EXISTS content_delta,
  ADD COLUMN IF NOT EXISTS content_document JSONB NOT NULL
    DEFAULT public.appflowy_document_from_plain_text(''),
  ADD COLUMN IF NOT EXISTS crdt_state_vector_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_update_base64 TEXT,
  ADD COLUMN IF NOT EXISTS crdt_snapshot_version BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_crdt_server_seq BIGINT NOT NULL DEFAULT 0;

ALTER TABLE public.note
  DROP CONSTRAINT IF EXISTS note_content_document_is_object,
  ADD CONSTRAINT note_content_document_is_object CHECK (
    jsonb_typeof(content_document) = 'object'
    AND content_document ? 'document'
  );

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

CREATE INDEX IF NOT EXISTS idx_note_user_scheduled_at
  ON public.note(user_id, scheduled_at)
  WHERE scheduled_at IS NOT NULL
    AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_note_reference
  ON public.note(reference_type, reference_id)
  WHERE reference_type IS NOT NULL
    AND reference_id IS NOT NULL
    AND deleted_at IS NULL;

ALTER TABLE public.daily_task
  DROP COLUMN IF EXISTS details;

DROP TYPE IF EXISTS public.note_status_enum;

CREATE TABLE public.note_crdt_update (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id UUID NOT NULL REFERENCES public.note(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  client_seq BIGINT NOT NULL,
  server_seq BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE,
  update_base64 TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(note_id, device_id, client_seq)
);

CREATE INDEX idx_note_crdt_update_note_server_seq
  ON public.note_crdt_update(note_id, server_seq);

ALTER TABLE public.note_crdt_update ENABLE ROW LEVEL SECURITY;

CREATE POLICY "note_crdt_update_select_own"
  ON public.note_crdt_update FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.note n
      WHERE n.id = note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "note_crdt_update_insert_own"
  ON public.note_crdt_update FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.note n
      WHERE n.id = note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

CREATE OR REPLACE FUNCTION public.push_note_crdt_updates(
  p_note_id UUID,
  p_updates JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_item JSONB;
  v_device_id TEXT;
  v_client_seq BIGINT;
  v_update_base64 TEXT;
  v_server_seq BIGINT;
  v_result JSONB := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.note n
    WHERE n.id = p_note_id
      AND n.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Note not found' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(jsonb_typeof(p_updates), '') <> 'array' THEN
    RAISE EXCEPTION 'p_updates must be a JSON array';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_updates)
  LOOP
    v_device_id := NULLIF(v_item->>'device_id', '');
    v_client_seq := NULLIF(v_item->>'client_seq', '')::BIGINT;
    v_update_base64 := NULLIF(v_item->>'update_base64', '');

    IF v_device_id IS NULL OR v_client_seq IS NULL OR v_update_base64 IS NULL THEN
      RAISE EXCEPTION 'Invalid CRDT update payload';
    END IF;

    v_server_seq := NULL;
    INSERT INTO public.note_crdt_update (
      note_id,
      device_id,
      client_seq,
      update_base64,
      created_at
    ) VALUES (
      p_note_id,
      v_device_id,
      v_client_seq,
      v_update_base64,
      COALESCE(NULLIF(v_item->>'created_at', '')::TIMESTAMPTZ, NOW())
    )
    ON CONFLICT(note_id, device_id, client_seq) DO NOTHING
    RETURNING server_seq INTO v_server_seq;

    IF v_server_seq IS NULL THEN
      SELECT server_seq INTO v_server_seq
      FROM public.note_crdt_update
      WHERE note_id = p_note_id
        AND device_id = v_device_id
        AND client_seq = v_client_seq;
    END IF;

    UPDATE public.note
    SET
      last_crdt_server_seq = GREATEST(last_crdt_server_seq, v_server_seq),
      updated_at = NOW()
    WHERE id = p_note_id;

    v_result := v_result || jsonb_build_array(
      jsonb_build_object(
        'device_id', v_device_id,
        'client_seq', v_client_seq,
        'server_seq', v_server_seq
      )
    );
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.push_note_crdt_updates(UUID, JSONB)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.push_note_crdt_updates(UUID, JSONB)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_note_crdt_updates(
  p_note_id UUID,
  p_after_server_seq BIGINT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.note n
    WHERE n.id = p_note_id
      AND n.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Note not found' USING ERRCODE = 'P0002';
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'note_id', note_id,
          'device_id', device_id,
          'client_seq', client_seq,
          'server_seq', server_seq,
          'update_base64', update_base64,
          'created_at', created_at
        )
        ORDER BY server_seq
      )
      FROM public.note_crdt_update
      WHERE note_id = p_note_id
        AND server_seq > COALESCE(p_after_server_seq, 0)
    ),
    '[]'::jsonb
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_note_crdt_updates(UUID, BIGINT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_note_crdt_updates(UUID, BIGINT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_note_snapshot(p_note_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_snapshot JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'note_id', n.id,
    'content_document', n.content_document,
    'plain_text', n.plain_text,
    'crdt_state_vector_base64', n.crdt_state_vector_base64,
    'crdt_snapshot_update_base64', n.crdt_snapshot_update_base64,
    'crdt_snapshot_version', n.crdt_snapshot_version,
    'last_crdt_server_seq', n.last_crdt_server_seq
  )
  INTO v_snapshot
  FROM public.note n
  WHERE n.id = p_note_id
    AND n.user_id = v_user_id;

  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'Note not found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_snapshot;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_note_snapshot(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_note_snapshot(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_plan_transaction(payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_plan_id UUID;
  v_ms JSONB;
  v_ms_index INTEGER;
  v_task JSONB;
  v_task_index INTEGER;
  v_ms_id UUID;
  v_task_id UUID;
  v_content_document JSONB;
  v_plain_text TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.plan (
    user_id,
    domain,
    original_prompt,
    answers,
    prompt_goal,
    prompt_current_status,
    prompt_available_time,
    prompt_constraints,
    title,
    ultimate_goal,
    total_duration,
    start_date,
    end_date,
    success_metrics,
    expert_advice
  ) VALUES (
    v_user_id,
    payload->>'domain',
    payload->>'original_prompt',
    COALESCE(payload->'answers', '{}'::jsonb),
    payload->>'prompt_goal',
    payload->>'prompt_current_status',
    payload->>'prompt_available_time',
    payload->>'prompt_constraints',
    payload->>'title',
    payload->>'ultimate_goal',
    payload->>'total_duration',
    (payload->>'start_date')::DATE,
    (payload->>'end_date')::DATE,
    COALESCE(payload->'success_metrics', '[]'::jsonb),
    COALESCE(payload->'expert_advice', '{}'::jsonb)
  )
  RETURNING id INTO v_plan_id;

  FOR v_ms, v_ms_index IN
    SELECT value, ordinality::INTEGER
    FROM jsonb_array_elements(payload->'milestones') WITH ORDINALITY
      AS milestones(value, ordinality)
  LOOP
    INSERT INTO public.milestone (
      plan_id,
      milestone_index,
      name,
      focus_objective,
      start_date,
      end_date
    ) VALUES (
      v_plan_id,
      COALESCE(NULLIF(v_ms->>'milestone_index', '')::INTEGER, v_ms_index),
      v_ms->>'name',
      v_ms->>'focus_objective',
      (v_ms->>'start_date')::DATE,
      (v_ms->>'end_date')::DATE
    )
    RETURNING id INTO v_ms_id;

    FOR v_task, v_task_index IN
      SELECT value, ordinality::INTEGER
      FROM jsonb_array_elements(v_ms->'tasks') WITH ORDINALITY
        AS tasks(value, ordinality)
    LOOP
      INSERT INTO public.daily_task (
        milestone_id,
        user_id,
        task_index,
        name,
        scheduled_start,
        scheduled_end,
        duration_minutes,
        resources_or_location,
        task_type
      ) VALUES (
        v_ms_id,
        v_user_id,
        COALESCE(NULLIF(v_task->>'task_index', '')::INTEGER, v_task_index),
        v_task->>'name',
        (v_task->>'scheduled_start')::TIMESTAMPTZ,
        (v_task->>'scheduled_end')::TIMESTAMPTZ,
        NULLIF(NULLIF(v_task->>'duration_minutes', '')::INTEGER, 0),
        v_task->>'resources_or_location',
        'ai_plan'
      )
      RETURNING id INTO v_task_id;

      IF v_task ? 'content_detail' THEN
        v_content_document := public.normalize_note_content_document(
          v_task->'content_detail',
          NULL
        );
        v_plain_text := public.plain_text_from_appflowy_document(
          v_content_document
        );

        INSERT INTO public.note (
          user_id,
          title,
          content_document,
          plain_text,
          reference_type,
          reference_id
        ) VALUES (
          v_user_id,
          COALESCE(v_task->>'name', ''),
          v_content_document,
          COALESCE(v_plain_text, ''),
          'task',
          v_task_id
        );
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_plan_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_plan_transaction(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_plan_detail(p_plan_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := (SELECT auth.uid());
  v_result  JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'plan', to_jsonb(p),
    'milestones', COALESCE(
      (
        SELECT jsonb_agg(milestone_obj ORDER BY ms_start, ms_created)
        FROM (
          SELECT
            to_jsonb(m) || jsonb_build_object(
              'tasks', COALESCE(
                (
                  SELECT jsonb_agg(to_jsonb(t) ORDER BY
                    t.scheduled_start NULLS LAST,
                    t.created_at)
                  FROM public.daily_task t
                  WHERE t.milestone_id = m.id
                ),
                '[]'::jsonb
              )
            ) AS milestone_obj,
            m.start_date AS ms_start,
            m.created_at AS ms_created
          FROM public.milestone m
          WHERE m.plan_id = p.id
        ) AS milestones_sub
      ),
      '[]'::jsonb
    )
  )
  INTO v_result
  FROM public.plan p
  WHERE p.id = p_plan_id
    AND p.user_id = v_user_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Plan not found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_plan_detail(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_plan_detail(UUID) TO authenticated;

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
