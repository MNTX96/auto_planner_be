export type CalendarProvider = 'google' | 'outlook';

export interface ProviderToken {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
  scope?: string;
  token_type?: string;
}

export interface ProviderProfile {
  email?: string;
  displayName?: string;
}

export interface ProviderCalendar {
  id: string;
  name: string;
}

export interface ProviderEvent {
  id: string;
  title: string;
  description?: string;
  start: string;
  end: string;
  updatedAt?: string;
  deleted: boolean;
}

export type CalendarProviderErrorCode =
  | 'missing_server_config'
  | 'provider_token_exchange_failed'
  | 'provider_calendar_access_failed';

export class CalendarProviderError extends Error {
  constructor(
    public readonly code: CalendarProviderErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'CalendarProviderError';
  }
}

interface TaskRow {
  id: string;
  name: string;
  details?: string | null;
  scheduled_start: string;
  scheduled_end: string;
  updated_at?: string | null;
}

const calendarName = 'OmniPlan';

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new CalendarProviderError(
      'missing_server_config',
      `${name} is not configured`,
    );
  }
  return value;
}

function optionalEnv(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim();
  return value && value.length > 0 ? value : undefined;
}

function requireGoogleClientSecret(): string {
  const clientSecret =
    optionalEnv('GOOGLE_CALENDAR_CLIENT_SECRET') ??
    optionalEnv('GOOGLE_WEB_CLIENT_SECRET');
  if (!clientSecret) {
    throw new CalendarProviderError(
      'missing_server_config',
      'GOOGLE_CALENDAR_CLIENT_SECRET or GOOGLE_WEB_CLIENT_SECRET is not configured',
    );
  }
  return clientSecret;
}

function providerErrorMessage(text: string, fallback: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return fallback;
  }

  try {
    const decoded = JSON.parse(trimmed) as Record<string, unknown>;
    const error = decoded.error;
    const details = [
      decoded.error_description,
      typeof error === 'object' && error != null
        ? (error as Record<string, unknown>).message
        : null,
      typeof error === 'string' ? error : null,
      decoded.message,
    ];
    for (const detail of details) {
      if (typeof detail === 'string' && detail.trim()) {
        return `${fallback}: ${detail.trim()}`.slice(0, 500);
      }
    }
  } catch {
    // Non-JSON provider responses are still useful for diagnosing setup issues.
  }

  return `${fallback}: ${trimmed}`.slice(0, 500);
}

async function fetchForm<T>(
  url: string,
  form: URLSearchParams,
): Promise<T> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new CalendarProviderError(
      'provider_token_exchange_failed',
      providerErrorMessage(
        text,
        `OAuth provider rejected the authorization code (${response.status})`,
      ),
    );
  }
  return JSON.parse(text) as T;
}

async function fetchJson<T>(
  url: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (response.status === 204) {
    return null as T;
  }
  const text = await response.text();
  if (!response.ok) {
    throw new CalendarProviderError(
      'provider_calendar_access_failed',
      providerErrorMessage(
        text,
        `Calendar provider request failed (${response.status})`,
      ),
    );
  }
  return JSON.parse(text) as T;
}

export async function exchangeOAuthCode({
  provider,
  code,
  codeVerifier,
  redirectUri,
}: {
  provider: CalendarProvider;
  code: string;
  codeVerifier?: string;
  redirectUri?: string;
}): Promise<ProviderToken> {
  if (provider === 'google') {
    const form = new URLSearchParams({
      client_id: requireEnv('GOOGLE_WEB_CLIENT_ID'),
      code,
      grant_type: 'authorization_code',
    });
    form.set('client_secret', requireGoogleClientSecret());
    if (redirectUri) {
      form.set('redirect_uri', redirectUri);
    }
    return fetchForm<ProviderToken>('https://oauth2.googleapis.com/token', form);
  }

  const form = new URLSearchParams({
    client_id: requireEnv('MICROSOFT_CLIENT_ID'),
    code,
    grant_type: 'authorization_code',
    redirect_uri: redirectUri ?? requireEnv('MICROSOFT_REDIRECT_URI'),
  });
  if (codeVerifier) {
    form.set('code_verifier', codeVerifier);
  }
  const clientSecret = Deno.env.get('MICROSOFT_CLIENT_SECRET');
  if (clientSecret) {
    form.set('client_secret', clientSecret);
  }
  return fetchForm<ProviderToken>(
    'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    form,
  );
}

export async function refreshOAuthToken({
  provider,
  refreshToken,
}: {
  provider: CalendarProvider;
  refreshToken: string;
}): Promise<ProviderToken> {
  if (provider === 'google') {
    const form = new URLSearchParams({
      client_id: requireEnv('GOOGLE_WEB_CLIENT_ID'),
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    });
    form.set('client_secret', requireGoogleClientSecret());
    return fetchForm<ProviderToken>('https://oauth2.googleapis.com/token', form);
  }

  const form = new URLSearchParams({
    client_id: requireEnv('MICROSOFT_CLIENT_ID'),
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  });
  const clientSecret = Deno.env.get('MICROSOFT_CLIENT_SECRET');
  if (clientSecret) {
    form.set('client_secret', clientSecret);
  }
  return fetchForm<ProviderToken>(
    'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    form,
  );
}

export async function getProviderProfile(
  provider: CalendarProvider,
  accessToken: string,
): Promise<ProviderProfile> {
  if (provider === 'google') {
    try {
      const data = await fetchJson<{ email?: string; name?: string }>(
        'https://openidconnect.googleapis.com/v1/userinfo',
        accessToken,
      );
      return { email: data.email, displayName: data.name };
    } catch {
      return {};
    }
  }

  const data = await fetchJson<{
    displayName?: string;
    mail?: string;
    userPrincipalName?: string;
  }>('https://graph.microsoft.com/v1.0/me', accessToken);
  return {
    email: data.mail ?? data.userPrincipalName,
    displayName: data.displayName,
  };
}

export async function ensureProviderCalendar(
  provider: CalendarProvider,
  accessToken: string,
  existingCalendarId?: string | null,
): Promise<ProviderCalendar> {
  if (provider === 'google') {
    if (existingCalendarId) {
      try {
        const existing = await fetchJson<{ id: string; summary: string }>(
          `https://www.googleapis.com/calendar/v3/calendars/${
            encodeURIComponent(existingCalendarId)
          }`,
          accessToken,
        );
        return { id: existing.id, name: existing.summary };
      } catch {
        // Recreate the app calendar if the stored calendar was removed.
      }
    }

    const created = await fetchJson<{ id: string; summary: string }>(
      'https://www.googleapis.com/calendar/v3/calendars',
      accessToken,
      {
        method: 'POST',
        body: JSON.stringify({
          summary: calendarName,
          description: 'Scheduled tasks synced from OmniPlan.',
        }),
      },
    );
    return { id: created.id, name: created.summary };
  }

  const list = await fetchJson<{
    value?: Array<{ id: string; name: string }>;
  }>(
    'https://graph.microsoft.com/v1.0/me/calendars?$select=id,name',
    accessToken,
  );
  const existing = list.value?.find((item) => item.name === calendarName);
  if (existing) {
    return { id: existing.id, name: existing.name };
  }

  const created = await fetchJson<{ id: string; name: string }>(
    'https://graph.microsoft.com/v1.0/me/calendars',
    accessToken,
    {
      method: 'POST',
      body: JSON.stringify({ name: calendarName }),
    },
  );
  return { id: created.id, name: created.name };
}

export async function fetchProviderEvents({
  provider,
  accessToken,
  calendarId,
  start,
  end,
}: {
  provider: CalendarProvider;
  accessToken: string;
  calendarId: string;
  start: Date;
  end: Date;
}): Promise<ProviderEvent[]> {
  if (provider === 'google') {
    const url = new URL(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(
        calendarId,
      )}/events`,
    );
    url.searchParams.set('singleEvents', 'true');
    url.searchParams.set('showDeleted', 'true');
    url.searchParams.set('timeMin', start.toISOString());
    url.searchParams.set('timeMax', end.toISOString());
    const data = await fetchJson<{
      items?: Array<{
        id?: string;
        status?: string;
        summary?: string;
        description?: string;
        start?: { dateTime?: string; date?: string };
        end?: { dateTime?: string; date?: string };
        updated?: string;
      }>;
    }>(url.toString(), accessToken);
    return (data.items ?? [])
      .filter((event) => !!event.id && !!(event.start?.dateTime ?? event.start?.date))
      .map((event) => ({
        id: event.id!,
        title: event.summary ?? 'Untitled',
        description: event.description,
        start: event.start?.dateTime ?? `${event.start!.date}T00:00:00Z`,
        end: event.end?.dateTime ?? `${event.end?.date ?? event.start!.date}T00:00:00Z`,
        updatedAt: event.updated,
        deleted: event.status === 'cancelled',
      }));
  }

  const url = new URL(
    `https://graph.microsoft.com/v1.0/me/calendars/${
      encodeURIComponent(calendarId)
    }/calendarView`,
  );
  url.searchParams.set('startDateTime', start.toISOString());
  url.searchParams.set('endDateTime', end.toISOString());
  url.searchParams.set(
    '$select',
    'id,subject,bodyPreview,start,end,lastModifiedDateTime,isCancelled',
  );
  const data = await fetchJson<{
    value?: Array<{
      id?: string;
      subject?: string;
      bodyPreview?: string;
      start?: { dateTime?: string };
      end?: { dateTime?: string };
      lastModifiedDateTime?: string;
      isCancelled?: boolean;
    }>;
  }>(url.toString(), accessToken, {
    headers: { Prefer: 'outlook.timezone="UTC"' },
  });
  return (data.value ?? [])
    .filter((event) => !!event.id && !!event.start?.dateTime)
    .map((event) => ({
      id: event.id!,
      title: event.subject ?? 'Untitled',
      description: event.bodyPreview,
      start: `${event.start!.dateTime}Z`,
      end: `${event.end?.dateTime ?? event.start!.dateTime}Z`,
      updatedAt: event.lastModifiedDateTime,
      deleted: event.isCancelled ?? false,
    }));
}

export async function upsertProviderEvent({
  provider,
  accessToken,
  calendarId,
  eventId,
  task,
}: {
  provider: CalendarProvider;
  accessToken: string;
  calendarId: string;
  eventId?: string | null;
  task: TaskRow;
}): Promise<{ eventId: string; updatedAt?: string }> {
  if (provider === 'google') {
    const body = {
      summary: task.name,
      description: task.details ?? undefined,
      start: { dateTime: new Date(task.scheduled_start).toISOString() },
      end: { dateTime: new Date(task.scheduled_end).toISOString() },
      extendedProperties: {
        private: {
          omni_plan_task_id: task.id,
          omni_plan_updated_at: task.updated_at ?? '',
        },
      },
    };
    const url = eventId
      ? `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(
        calendarId,
      )}/events/${encodeURIComponent(eventId)}`
      : `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(
        calendarId,
      )}/events`;
    const data = await fetchJson<{ id: string; updated?: string }>(
      url,
      accessToken,
      {
        method: eventId ? 'PATCH' : 'POST',
        body: JSON.stringify(body),
      },
    );
    return { eventId: data.id, updatedAt: data.updated };
  }

  const body = {
    subject: task.name,
    body: {
      contentType: 'text',
      content: task.details ?? '',
    },
    start: {
      dateTime: new Date(task.scheduled_start).toISOString().replace('Z', ''),
      timeZone: 'UTC',
    },
    end: {
      dateTime: new Date(task.scheduled_end).toISOString().replace('Z', ''),
      timeZone: 'UTC',
    },
  };
  const url = eventId
    ? `https://graph.microsoft.com/v1.0/me/calendars/${
      encodeURIComponent(calendarId)
    }/events/${encodeURIComponent(eventId)}`
    : `https://graph.microsoft.com/v1.0/me/calendars/${
      encodeURIComponent(calendarId)
    }/events`;
  const data = await fetchJson<{ id: string; lastModifiedDateTime?: string }>(
    url,
    accessToken,
    {
      method: eventId ? 'PATCH' : 'POST',
      body: JSON.stringify(body),
    },
  );
  return { eventId: data.id, updatedAt: data.lastModifiedDateTime };
}
