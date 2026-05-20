import { getServiceRoleClient, getSupabaseClient } from '../_shared/auth.ts';
import { encryptJson } from '../_shared/calendar_crypto.ts';
import {
  CalendarProvider,
  CalendarProviderError,
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

type CalendarOauthExchangeFailureCode =
  | 'missing_server_config'
  | 'provider_token_exchange_failed'
  | 'provider_calendar_access_failed'
  | 'calendar_connection_save_failed'
  | 'calendar_oauth_exchange_failed';

class CalendarOauthExchangeError extends Error {
  constructor(
    public readonly code: CalendarOauthExchangeFailureCode,
    message: string,
  ) {
    super(message);
    this.name = 'CalendarOauthExchangeError';
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  if (typeof error === 'object' && error != null && 'message' in error) {
    const message = (error as { message?: unknown }).message;
    if (typeof message === 'string') {
      return message;
    }
  }
  return String(error);
}

function classifyError(error: unknown): {
  code: CalendarOauthExchangeFailureCode;
  message: string;
  status: number;
} {
  if (error instanceof CalendarProviderError) {
    return {
      code: error.code,
      message: error.message,
      status: error.code === 'missing_server_config' ? 500 : 502,
    };
  }

  if (error instanceof CalendarOauthExchangeError) {
    return {
      code: error.code,
      message: error.message,
      status: 500,
    };
  }

  const message = errorMessage(error);
  if (message.includes('is not configured') || message.includes('not set')) {
    return {
      code: 'missing_server_config',
      message,
      status: 500,
    };
  }

  return {
    code: 'calendar_oauth_exchange_failed',
    message: 'Calendar OAuth exchange failed',
    status: 500,
  };
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
      throw new CalendarOauthExchangeError(
        'calendar_connection_save_failed',
        connectionError.message ?? 'Could not save calendar connection.',
      );
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
      throw new CalendarOauthExchangeError(
        'calendar_connection_save_failed',
        tokenError.message ?? 'Could not save calendar token.',
      );
    }

    return jsonResponse({ connection });
  } catch (error) {
    console.error('calendar-oauth-exchange failed', error);
    const classified = classifyError(error);
    try {
      await getServiceRoleClient()
        .from('calendar_sync_connection')
        .upsert(
          {
            user_id: user.id,
            provider: body.provider,
            enabled: false,
            last_error: classified.message,
          },
          { onConflict: 'user_id,provider' },
        );
    } catch (saveError) {
      console.error('calendar-oauth-exchange failure save failed', saveError);
    }
    return jsonResponse(
      { error: classified.message, code: classified.code },
      classified.status,
    );
  }
});
