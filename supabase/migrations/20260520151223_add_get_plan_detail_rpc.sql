-- ============================================================
-- get_plan_detail RPC
--
-- Returns a plan with its milestones and each milestone's tasks
-- in a single round-trip, eliminating the N+1 query pattern on
-- the client (1 plan + 1 milestones + N tasks → 1 RPC call).
--
-- Security: SECURITY INVOKER → existing RLS on plan / milestone /
-- daily_task enforces ownership. The function only sees rows the
-- caller can already SELECT.
-- ============================================================

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
                  FROM daily_task t
                  WHERE t.milestone_id = m.id
                ),
                '[]'::jsonb
              )
            ) AS milestone_obj,
            m.start_date AS ms_start,
            m.created_at AS ms_created
          FROM milestone m
          WHERE m.plan_id = p.id
        ) AS milestones_sub
      ),
      '[]'::jsonb
    )
  )
  INTO v_result
  FROM plan p
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
