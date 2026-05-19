import { getServiceRoleClient, getSupabaseClient } from '../_shared/auth.ts';
import { encryptJson } from '../_shared/calendar_crypto.ts';
import {
  CalendarProvider,
  ensureProviderCalendar,
  exchangeOAuthCode,
  getProviderProfile,
} from '../_shared/calendar_provider.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';

interface CalendarOauthExchangeRequest {
  provider: CalendarProvider;
  code: string;
  code_verifier?: string;
  redirect_uri?: string;
  account_email?: string;
}

function isProvider(value: string): value is CalendarProvider {
  return value === 'google' || value === 'outlook';
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<CalendarOauthExchangeRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (!body.provider || !isProvider(body.provider)) {
    return jsonResponse({ error: 'provider must be google or outlook' }, 400);
  }
  if (!body.code?.trim()) {
    return jsonResponse({ error: 'code is required' }, 400);
  }

  const supabase = getSupabaseClient(req);
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  try {
    const token = await exchangeOAuthCode({
      provider: body.provider,
      code: body.code,
      codeVerifier: body.code_verifier,
      redirectUri: body.redirect_uri,
    });
    const profile = await getProviderProfile(body.provider, token.access_token);
    const calendar = await ensureProviderCalendar(
      body.provider,
      token.access_token,
    );
    const service = getServiceRoleClient();
    const expiresAt = token.expires_in
      ? new Date(Date.now() + token.expires_in * 1000).toISOString()
      : null;
    const scopes = token.scope?.split(/\s+/).filter(Boolean) ?? [];
    const encryptedAccessToken = await encryptJson({
      value: token.access_token,
    });
    const encryptedRefreshToken = token.refresh_token
      ? await encryptJson({ value: token.refresh_token })
      : null;

    const { data: connection, error: connectionError } = await service
      .from('calendar_sync_connection')
      .upsert(
        {
          user_id: user.id,
          provider: body.provider,
          enabled: true,
          account_email:
            body.account_email ?? profile.email ?? profile.displayName ?? null,
          provider_calendar_id: calendar.id,
          provider_calendar_name: calendar.name,
          last_error: null,
          last_synced_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,provider' },
      )
      .select()
      .single();
    if (connectionError) {
      throw connectionError;
    }

    const tokenPayload: Record<string, unknown> = {
      user_id: user.id,
      provider: body.provider,
      access_token_encrypted: encryptedAccessToken,
      expires_at: expiresAt,
      scopes,
      token_type: token.token_type ?? null,
    };
    if (encryptedRefreshToken) {
      tokenPayload.refresh_token_encrypted = encryptedRefreshToken;
    }
    const { error: tokenError } = await service
      .from('calendar_sync_token')
      .upsert(tokenPayload, { onConflict: 'user_id,provider' });
    if (tokenError) {
      throw tokenError;
    }

    return jsonResponse({ connection });
  } catch (error) {
    console.error('calendar-oauth-exchange failed', error);
    await getServiceRoleClient()
      .from('calendar_sync_connection')
      .upsert(
        {
          user_id: user.id,
          provider: body.provider,
          enabled: false,
          last_error: error instanceof Error ? error.message : String(error),
        },
        { onConflict: 'user_id,provider' },
      );
    return jsonResponse({ error: 'Calendar OAuth exchange failed' }, 500);
  }
});
