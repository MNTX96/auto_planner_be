import { getServiceRoleClient, getSupabaseClient } from '../_shared/auth.ts';
import {
  documentFromPlainText,
  plainTextFromDocument,
} from '../_shared/appflowy_document.ts';
import { decryptJson, encryptJson } from '../_shared/calendar_crypto.ts';
import {
  CalendarProvider,
  ensureProviderCalendar,
  fetchProviderEvents,
  refreshOAuthToken,
  upsertProviderEvent,
} from '../_shared/calendar_provider.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';

type CalendarSyncMode = 'full' | 'push_task';

interface CalendarSyncRequest {
  provider?: CalendarProvider;
  mode?: CalendarSyncMode;
  task_id?: string;
}

interface ConnectionRow {
  user_id: string;
  provider: CalendarProvider;
  provider_calendar_id?: string | null;
  provider_calendar_name?: string | null;
}

interface TokenRow {
  access_token_encrypted: string;
  refresh_token_encrypted?: string | null;
  expires_at?: string | null;
  scopes?: string[] | null;
  token_type?: string | null;
}

interface TaskRow {
  id: string;
  user_id: string;
  name: string;
  description?: string | null;
  scheduled_start: string;
  scheduled_end: string;
  updated_at?: string | null;
}

interface NoteRow {
  id: string;
  reference_id: string;
  plain_text?: string | null;
}

interface EventMappingRow {
  id: string;
  task_id: string;
  provider_event_id: string;
  provider_calendar_id?: string | null;
  provider_updated_at?: string | null;
  task_updated_at?: string | null;
}

interface TokenSecret {
  value: string;
}

function isProvider(value: string): value is CalendarProvider {
  return value === 'google' || value === 'outlook';
}

async function latestTaskNoteTextByTaskId(
  service: ReturnType<typeof getServiceRoleClient>,
  userId: string,
  taskIds: string[],
): Promise<Map<string, string>> {
  if (taskIds.length === 0) {
    return new Map();
  }

  const { data: notes, error } = await service
    .from('note')
    .select('id,reference_id,plain_text,updated_at,created_at')
    .eq('user_id', userId)
    .eq('reference_type', 'task')
    .in('reference_id', taskIds)
    .is('deleted_at', null)
    .order('updated_at', { ascending: false })
    .order('created_at', { ascending: false })
    .returns<NoteRow[]>();
  if (error) {
    throw error;
  }

  const descriptions = new Map<string, string>();
  for (const note of notes ?? []) {
    if (!descriptions.has(note.reference_id)) {
      descriptions.set(note.reference_id, note.plain_text ?? '');
    }
  }
  return descriptions;
}

async function upsertTaskNoteFromDescription({
  service,
  userId,
  taskId,
  title,
  description,
}: {
  service: ReturnType<typeof getServiceRoleClient>;
  userId: string;
  taskId: string;
  title: string;
  description?: string | null;
}): Promise<void> {
  if (description == null) {
    return;
  }

  const contentDocument = documentFromPlainText(description);
  const notePayload = {
    user_id: userId,
    title,
    content_document: contentDocument,
    plain_text: plainTextFromDocument(contentDocument),
    reference_type: 'task',
    reference_id: taskId,
  };

  const { data: existingNote, error: selectError } = await service
    .from('note')
    .select('id')
    .eq('user_id', userId)
    .eq('reference_type', 'task')
    .eq('reference_id', taskId)
    .is('deleted_at', null)
    .order('updated_at', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (selectError) {
    throw selectError;
  }

  if (existingNote?.id) {
    const { error } = await service
      .from('note')
      .update(notePayload)
      .eq('id', existingNote.id)
      .eq('user_id', userId);
    if (error) {
      throw error;
    }
    return;
  }

  const { error } = await service
    .from('note')
    .insert(notePayload);
  if (error) {
    throw error;
  }
}

function eventWindow(): { start: Date; end: Date } {
  const now = Date.now();
  return {
    start: new Date(now - 30 * 24 * 60 * 60 * 1000),
    end: new Date(now + 90 * 24 * 60 * 60 * 1000),
  };
}

function plusExpiresIn(expiresIn?: number): string | null {
  return expiresIn
    ? new Date(Date.now() + expiresIn * 1000).toISOString()
    : null;
}

function isProviderNewer(
  providerUpdatedAt?: string | null,
  taskUpdatedAt?: string | null,
): boolean {
  if (!providerUpdatedAt || !taskUpdatedAt) {
    return true;
  }
  return new Date(providerUpdatedAt).getTime() >
    new Date(taskUpdatedAt).getTime();
}

async function loadAccessToken(
  service: ReturnType<typeof getServiceRoleClient>,
  userId: string,
  provider: CalendarProvider,
): Promise<string> {
  const { data: tokenRow, error } = await service
    .from('calendar_sync_token')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', provider)
    .returns<TokenRow>()
    .single();
  if (error || !tokenRow) {
    throw error ?? new Error('Calendar token is missing');
  }

  const accessToken = await decryptJson<TokenSecret>(
    tokenRow.access_token_encrypted,
  );
  const expiresAt = tokenRow.expires_at
    ? new Date(tokenRow.expires_at).getTime()
    : 0;
  const shouldRefresh = expiresAt > 0 && expiresAt - Date.now() < 60_000;
  if (!shouldRefresh || !tokenRow.refresh_token_encrypted) {
    return accessToken.value;
  }

  const refreshToken = await decryptJson<TokenSecret>(
    tokenRow.refresh_token_encrypted,
  );
  const refreshed = await refreshOAuthToken({
    provider,
    refreshToken: refreshToken.value,
  });
  const updates: Record<string, unknown> = {
    access_token_encrypted: await encryptJson({ value: refreshed.access_token }),
    expires_at: plusExpiresIn(refreshed.expires_in),
    scopes: refreshed.scope?.split(/\s+/).filter(Boolean) ?? tokenRow.scopes,
    token_type: refreshed.token_type ?? tokenRow.token_type,
  };
  if (refreshed.refresh_token) {
    updates.refresh_token_encrypted = await encryptJson({
      value: refreshed.refresh_token,
    });
  }
  const { error: updateError } = await service
    .from('calendar_sync_token')
    .update(updates)
    .eq('user_id', userId)
    .eq('provider', provider);
  if (updateError) {
    throw updateError;
  }
  return refreshed.access_token;
}

async function ensureCalendarId(
  service: ReturnType<typeof getServiceRoleClient>,
  connection: ConnectionRow,
  accessToken: string,
): Promise<string> {
  if (connection.provider_calendar_id) {
    return connection.provider_calendar_id;
  }
  const calendar = await ensureProviderCalendar(connection.provider, accessToken);
  const { error } = await service
    .from('calendar_sync_connection')
    .update({
      provider_calendar_id: calendar.id,
      provider_calendar_name: calendar.name,
    })
    .eq('user_id', connection.user_id)
    .eq('provider', connection.provider);
  if (error) {
    throw error;
  }
  return calendar.id;
}

async function pushTasks({
  service,
  userId,
  provider,
  accessToken,
  calendarId,
  taskId,
}: {
  service: ReturnType<typeof getServiceRoleClient>;
  userId: string;
  provider: CalendarProvider;
  accessToken: string;
  calendarId: string;
  taskId?: string;
}): Promise<number> {
  let query = service
    .from('daily_task')
    .select('id,user_id,name,scheduled_start,scheduled_end,updated_at')
    .eq('user_id', userId)
    .not('scheduled_start', 'is', null)
    .not('scheduled_end', 'is', null);
  if (taskId) {
    query = query.eq('id', taskId);
  }
  const { data: tasks, error } = await query.returns<TaskRow[]>();
  if (error) {
    throw error;
  }

  const noteTextByTaskId = await latestTaskNoteTextByTaskId(
    service,
    userId,
    (tasks ?? []).map((task) => task.id),
  );

  let count = 0;
  for (const task of tasks ?? []) {
    const { data: mapping, error: mappingError } = await service
      .from('calendar_sync_event')
      .select('*')
      .eq('user_id', userId)
      .eq('provider', provider)
      .eq('task_id', task.id)
      .returns<EventMappingRow>()
      .maybeSingle();
    if (mappingError) {
      throw mappingError;
    }

    const providerResult = await upsertProviderEvent({
      provider,
      accessToken,
      calendarId,
      eventId: mapping?.provider_event_id,
      task: {
        ...task,
        description: noteTextByTaskId.get(task.id) ?? null,
      },
    });
    const { error: upsertError } = await service
      .from('calendar_sync_event')
      .upsert(
        {
          user_id: userId,
          task_id: task.id,
          provider,
          provider_event_id: providerResult.eventId,
          provider_calendar_id: calendarId,
          provider_updated_at: providerResult.updatedAt ?? null,
          task_updated_at: task.updated_at ?? null,
          provider_deleted: false,
        },
        { onConflict: 'user_id,task_id,provider' },
      );
    if (upsertError) {
      throw upsertError;
    }
    count += 1;
  }
  return count;
}

async function pullProviderEvents({
  service,
  userId,
  provider,
  accessToken,
  calendarId,
}: {
  service: ReturnType<typeof getServiceRoleClient>;
  userId: string;
  provider: CalendarProvider;
  accessToken: string;
  calendarId: string;
}): Promise<number> {
  const { start, end } = eventWindow();
  const events = await fetchProviderEvents({
    provider,
    accessToken,
    calendarId,
    start,
    end,
  });

  let count = 0;
  for (const event of events) {
    const { data: mapping, error: mappingError } = await service
      .from('calendar_sync_event')
      .select('*')
      .eq('user_id', userId)
      .eq('provider', provider)
      .eq('provider_event_id', event.id)
      .returns<EventMappingRow>()
      .maybeSingle();
    if (mappingError) {
      throw mappingError;
    }

    if (event.deleted) {
      if (mapping) {
        const { error: deletedError } = await service
          .from('calendar_sync_event')
          .update({ provider_deleted: true })
          .eq('id', mapping.id);
        if (deletedError) {
          throw deletedError;
        }
      }
      continue;
    }

    if (mapping) {
      const { data: task, error: taskError } = await service
        .from('daily_task')
        .select('id,updated_at')
        .eq('id', mapping.task_id)
        .eq('user_id', userId)
        .returns<{ id: string; updated_at?: string | null }>()
        .maybeSingle();
      if (taskError) {
        throw taskError;
      }
      if (task && isProviderNewer(event.updatedAt, task.updated_at)) {
        const { error: updateError } = await service
          .from('daily_task')
          .update({
            name: event.title,
            scheduled_start: new Date(event.start).toISOString(),
            scheduled_end: new Date(event.end).toISOString(),
          })
          .eq('id', task.id)
          .eq('user_id', userId);
        if (updateError) {
          throw updateError;
        }
        await upsertTaskNoteFromDescription({
          service,
          userId,
          taskId: task.id,
          title: event.title,
          description: event.description,
        });
        count += 1;
      }
      const { error: mappingUpdateError } = await service
        .from('calendar_sync_event')
        .update({
          provider_calendar_id: calendarId,
          provider_updated_at: event.updatedAt ?? null,
          provider_deleted: false,
        })
        .eq('id', mapping.id);
      if (mappingUpdateError) {
        throw mappingUpdateError;
      }
      continue;
    }

    const { data: insertedTask, error: insertError } = await service
      .from('daily_task')
      .insert({
        user_id: userId,
        task_index: 0,
        name: event.title,
        scheduled_start: new Date(event.start).toISOString(),
        scheduled_end: new Date(event.end).toISOString(),
        task_type: 'manual_single',
        status: 'pending',
        priority: 'medium',
        calendar_event_id: null,
      })
      .select('id,updated_at')
      .returns<{ id: string; updated_at?: string | null }>()
      .single();
    if (insertError || !insertedTask) {
      throw insertError ?? new Error('Could not import calendar event');
    }
    await upsertTaskNoteFromDescription({
      service,
      userId,
      taskId: insertedTask.id,
      title: event.title,
      description: event.description,
    });
    const { error: upsertError } = await service
      .from('calendar_sync_event')
      .upsert(
        {
          user_id: userId,
          task_id: insertedTask.id,
          provider,
          provider_event_id: event.id,
          provider_calendar_id: calendarId,
          provider_updated_at: event.updatedAt ?? null,
          task_updated_at: insertedTask.updated_at ?? null,
          provider_deleted: false,
        },
        { onConflict: 'user_id,provider,provider_event_id' },
      );
    if (upsertError) {
      throw upsertError;
    }
    count += 1;
  }
  return count;
}

async function syncConnection({
  service,
  connection,
  mode,
  taskId,
}: {
  service: ReturnType<typeof getServiceRoleClient>;
  connection: ConnectionRow;
  mode: CalendarSyncMode;
  taskId?: string;
}): Promise<{ provider: CalendarProvider; pushed: number; pulled: number }> {
  const accessToken = await loadAccessToken(
    service,
    connection.user_id,
    connection.provider,
  );
  const calendarId = await ensureCalendarId(service, connection, accessToken);
  const pulled = mode === 'full'
    ? await pullProviderEvents({
      service,
      userId: connection.user_id,
      provider: connection.provider,
      accessToken,
      calendarId,
    })
    : 0;
  const pushed = await pushTasks({
    service,
    userId: connection.user_id,
    provider: connection.provider,
    accessToken,
    calendarId,
    taskId,
  });
  await service
    .from('calendar_sync_connection')
    .update({
      last_synced_at: new Date().toISOString(),
      last_error: null,
    })
    .eq('user_id', connection.user_id)
    .eq('provider', connection.provider);
  return { provider: connection.provider, pushed, pulled };
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<CalendarSyncRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (body.provider && !isProvider(body.provider)) {
    return jsonResponse({ error: 'provider must be google or outlook' }, 400);
  }
  const mode = body.mode ?? 'full';
  if (mode !== 'full' && mode !== 'push_task') {
    return jsonResponse({ error: 'mode must be full or push_task' }, 400);
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
  let query = service
    .from('calendar_sync_connection')
    .select('*')
    .eq('user_id', user.id)
    .eq('enabled', true);
  if (body.provider) {
    query = query.eq('provider', body.provider);
  }
  const { data: connections, error: connectionError } = await query.returns<
    ConnectionRow[]
  >();
  if (connectionError) {
    return jsonResponse({ error: connectionError.message }, 500);
  }

  const results = [];
  for (const connection of connections ?? []) {
    try {
      results.push(
        await syncConnection({
          service,
          connection,
          mode,
          taskId: body.task_id,
        }),
      );
    } catch (error) {
      console.error('calendar-sync provider failed', connection.provider, error);
      await service
        .from('calendar_sync_connection')
        .update({
          last_error: error instanceof Error ? error.message : String(error),
        })
        .eq('user_id', user.id)
        .eq('provider', connection.provider);
      results.push({
        provider: connection.provider,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return jsonResponse({ results });
});
