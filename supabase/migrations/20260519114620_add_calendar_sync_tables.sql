-- Stores per-user external calendar sync configuration and event mappings.
-- Provider OAuth tokens are stored separately and encrypted by Edge Functions.

CREATE TABLE public.calendar_sync_connection (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('google', 'outlook')),
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  account_email TEXT,
  provider_calendar_id TEXT,
  provider_calendar_name TEXT,
  sync_cursor TEXT,
  last_synced_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider)
);

CREATE TRIGGER calendar_sync_connection_set_updated_at
  BEFORE UPDATE ON public.calendar_sync_connection
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_calendar_sync_connection_user_id
  ON public.calendar_sync_connection(user_id);

CREATE TABLE public.calendar_sync_token (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('google', 'outlook')),
  access_token_encrypted TEXT NOT NULL,
  refresh_token_encrypted TEXT,
  expires_at TIMESTAMPTZ,
  scopes TEXT[] NOT NULL DEFAULT '{}',
  token_type TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider)
);

CREATE TRIGGER calendar_sync_token_set_updated_at
  BEFORE UPDATE ON public.calendar_sync_token
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_calendar_sync_token_user_id
  ON public.calendar_sync_token(user_id);

CREATE TABLE public.calendar_sync_event (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.daily_task(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('google', 'outlook')),
  provider_event_id TEXT NOT NULL,
  provider_calendar_id TEXT,
  provider_updated_at TIMESTAMPTZ,
  task_updated_at TIMESTAMPTZ,
  provider_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, task_id, provider),
  UNIQUE (user_id, provider, provider_event_id)
);

CREATE TRIGGER calendar_sync_event_set_updated_at
  BEFORE UPDATE ON public.calendar_sync_event
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_calendar_sync_event_user_provider
  ON public.calendar_sync_event(user_id, provider);

CREATE INDEX idx_calendar_sync_event_task_id
  ON public.calendar_sync_event(task_id);

ALTER TABLE public.calendar_sync_connection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calendar_sync_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calendar_sync_event ENABLE ROW LEVEL SECURITY;

CREATE POLICY "calendar_sync_connection_select_own"
  ON public.calendar_sync_connection
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_connection_insert_own"
  ON public.calendar_sync_connection
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_connection_update_own"
  ON public.calendar_sync_connection
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_connection_delete_own"
  ON public.calendar_sync_connection
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_token_select_none"
  ON public.calendar_sync_token
  FOR SELECT TO authenticated
  USING (FALSE);

CREATE POLICY "calendar_sync_token_insert_none"
  ON public.calendar_sync_token
  FOR INSERT TO authenticated
  WITH CHECK (FALSE);

CREATE POLICY "calendar_sync_token_update_none"
  ON public.calendar_sync_token
  FOR UPDATE TO authenticated
  USING (FALSE)
  WITH CHECK (FALSE);

CREATE POLICY "calendar_sync_token_delete_none"
  ON public.calendar_sync_token
  FOR DELETE TO authenticated
  USING (FALSE);

CREATE POLICY "calendar_sync_event_select_own"
  ON public.calendar_sync_event
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_event_insert_own"
  ON public.calendar_sync_event
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_event_update_own"
  ON public.calendar_sync_event
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "calendar_sync_event_delete_own"
  ON public.calendar_sync_event
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
