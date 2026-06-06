-- Move task detail content into task-linked notes and remove draft notes.

CREATE OR REPLACE FUNCTION public.quill_delta_from_plain_text(p_text TEXT)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('insert', COALESCE(p_text, '') || E'\n')
  );
$$;

CREATE OR REPLACE FUNCTION public.normalize_note_content_delta(
  p_delta JSONB,
  p_fallback_text TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_delta) = 'array' AND jsonb_array_length(p_delta) > 0
      THEN p_delta
    ELSE public.quill_delta_from_plain_text(COALESCE(p_fallback_text, ''))
  END;
$$;

CREATE OR REPLACE FUNCTION public.plain_text_from_quill_delta(p_delta JSONB)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT regexp_replace(
    COALESCE(
      (
        SELECT string_agg(
          CASE
            WHEN jsonb_typeof(op->'insert') = 'string' THEN op->>'insert'
            ELSE ''
          END,
          ''
          ORDER BY ordinality
        )
        FROM jsonb_array_elements(
          CASE
            WHEN jsonb_typeof(p_delta) = 'array' THEN p_delta
            ELSE '[]'::jsonb
          END
        ) WITH ORDINALITY AS delta_ops(op, ordinality)
      ),
      ''
    ),
    E'\\n$',
    ''
  );
$$;

CREATE OR REPLACE FUNCTION public.append_plain_text_to_quill_delta(
  p_delta JSONB,
  p_text TEXT
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN btrim(COALESCE(public.plain_text_from_quill_delta(p_delta), '')) = ''
      THEN public.quill_delta_from_plain_text(p_text)
    ELSE public.normalize_note_content_delta(p_delta)
      || jsonb_build_array(jsonb_build_object('insert', E'\n' || p_text || E'\n'))
  END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'note'
      AND column_name = 'status'
  ) THEN
    UPDATE public.note
    SET status = 'published'
    WHERE status = 'draft';
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'daily_task'
      AND column_name = 'details'
  ) THEN
    DROP TABLE IF EXISTS task_details_to_note_backfill;

    CREATE TEMP TABLE task_details_to_note_backfill
    ON COMMIT DROP
    AS
      SELECT
        id,
        user_id,
        name,
        color,
        details,
        created_at
      FROM public.daily_task
      WHERE details IS NOT NULL
        AND btrim(details) <> ''
        AND deleted_at IS NULL;

    WITH latest_note AS (
      SELECT DISTINCT ON (n.reference_id)
        n.id AS note_id,
        n.reference_id AS task_id
      FROM public.note n
      JOIN task_details_to_note_backfill t ON t.id = n.reference_id
      WHERE n.reference_type = 'task'
        AND n.deleted_at IS NULL
      ORDER BY n.reference_id, n.updated_at DESC NULLS LAST, n.created_at DESC, n.id
    )
    UPDATE public.note n
    SET
      content_delta = public.append_plain_text_to_quill_delta(n.content_delta, t.details),
      plain_text = CASE
        WHEN btrim(COALESCE(n.plain_text, '')) = '' THEN t.details
        ELSE n.plain_text || E'\n\n' || t.details
      END,
      updated_at = NOW()
    FROM latest_note ln
    JOIN task_details_to_note_backfill t ON t.id = ln.task_id
    WHERE n.id = ln.note_id;

    INSERT INTO public.note (
      user_id,
      title,
      content_delta,
      plain_text,
      reference_type,
      reference_id,
      color,
      created_at,
      updated_at
    )
    SELECT
      t.user_id,
      COALESCE(t.name, ''),
      public.quill_delta_from_plain_text(t.details),
      t.details,
      'task',
      t.id,
      t.color,
      COALESCE(t.created_at, NOW()),
      NOW()
    FROM task_details_to_note_backfill t
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.note n
      WHERE n.reference_type = 'task'
        AND n.reference_id = t.id
        AND n.deleted_at IS NULL
    );

    DROP TABLE IF EXISTS task_details_to_note_backfill;
  END IF;
END;
$$;

DROP INDEX IF EXISTS public.idx_note_user_status_updated;
DROP INDEX IF EXISTS public.idx_note_user_scheduled_at;
DROP INDEX IF EXISTS public.idx_note_reference;

ALTER TABLE public.note
  DROP COLUMN IF EXISTS status;

DROP TYPE IF EXISTS public.note_status_enum;

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
  v_content_delta JSONB;
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

      IF v_task ? 'content_detail'
        OR btrim(COALESCE(v_task->>'details', '')) <> ''
      THEN
        v_content_delta := public.normalize_note_content_delta(
          v_task->'content_detail',
          v_task->>'details'
        );
        v_plain_text := public.plain_text_from_quill_delta(v_content_delta);

        INSERT INTO public.note (
          user_id,
          title,
          content_delta,
          plain_text,
          reference_type,
          reference_id
        ) VALUES (
          v_user_id,
          COALESCE(v_task->>'name', ''),
          v_content_delta,
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
