-- Supabase grants EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated by default.
-- REVOKE FROM PUBLIC does not override those explicit role grants.
-- Explicitly revoke from anon and authenticated for SECURITY DEFINER functions
-- that must never be called directly via REST /rpc/.

-- handle_new_user: trigger-only, must not be callable via API
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- rls_auto_enable: Supabase system function, must not be callable via API
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'rls_auto_enable'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;
  END IF;
END;
$$;
