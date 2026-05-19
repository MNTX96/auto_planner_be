import { getServiceRoleClient, getSupabaseClient } from '../_shared/auth.ts';
import {
  CalendarProvider,
} from '../_shared/calendar_provider.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';

interface CalendarDisconnectRequest {
  provider: CalendarProvider;
}

function isProvider(value: string): value is CalendarProvider {
  return value === 'google' || value === 'outlook';
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<CalendarDisconnectRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (!body.provider || !isProvider(body.provider)) {
    return jsonResponse({ error: 'provider must be google or outlook' }, 400);
  }

  const supabase = getSupabaseClient(req);
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  const service = getServiceRoleClient();
  const { error: connectionError } = await service
    .from('calendar_sync_connection')
    .update({
      enabled: false,
      sync_cursor: null,
      last_error: null,
    })
    .eq('user_id', user.id)
    .eq('provider', body.provider);
  if (connectionError) {
    console.error('calendar-disconnect connection failed', connectionError);
    return jsonResponse({ error: connectionError.message }, 500);
  }

  const { error: tokenError } = await service
    .from('calendar_sync_token')
    .delete()
    .eq('user_id', user.id)
    .eq('provider', body.provider);
  if (tokenError) {
    console.error('calendar-disconnect token failed', tokenError);
    return jsonResponse({ error: tokenError.message }, 500);
  }

  return jsonResponse({ ok: true });
});
