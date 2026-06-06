import { getSupabaseClient } from '../_shared/auth.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';
import {
  normalizeQuillDelta,
  plainTextFromDelta,
} from '../_shared/quill_delta.ts';
import {
  formatTimezoneOffset,
  normalizeTimestampToUtcIso,
  toOffsetIsoString,
} from '../_shared/time.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface CreateTaskAiRequest {
  text: string;
  timezone_offset_minutes?: number;
}

interface AiTask {
  name: string;
  scheduled_start: string;
  scheduled_end: string;
  content_detail?: unknown;
  priority: 'low' | 'medium' | 'high' | 'critical';
}

function hasOwnKey(value: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<CreateTaskAiRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (!body.text?.trim()) {
    return jsonResponse({ error: 'text is required' }, 400);
  }

  const supabase = getSupabaseClient(req);

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  const offsetMinutes = body.timezone_offset_minutes ?? 420;
  const tzString = formatTimezoneOffset(offsetMinutes);

  const utcNow = new Date();
  const localIsoString = toOffsetIsoString(utcNow, offsetMinutes);
  const localDateStr = localIsoString.split('T')[0];

  const systemPrompt = `You are a highly intelligent NLP task scheduling assistant.
CURRENT LOCAL DATE AND TIME: ${localIsoString}

Parse the user's natural language input (often Vietnamese) into a structured JSON array of tasks.

### TIME INTERPRETATION RULES:
- "hôm nay" / "today" -> ${localDateStr}
- "ngày mai" / "mai" / "tomorrow" -> The next calendar day.
- "mốt" / "ngày kia" -> 2 days from today.
- "sáng" (morning) -> default 08:00.
- "trưa" (noon) -> default 12:00.
- "chiều" (afternoon) -> default 14:00.
- "tối" (evening/night) -> default 19:00.
- "cuối tuần" (weekend) -> The upcoming Saturday.
- "tuần sau" (next week) -> The upcoming Monday.
- If an exact hour is specified (e.g., "9h", "9 rưỡi"), use it.
- If NO duration is implied, assume exactly 1 hour.

### PRIORITY INFERENCE RULES (4 LEVELS):
Evaluate the urgency and importance of the task based on keywords or context:
1. "critical": Absolute emergencies, life-or-death, or top-tier deadlines (e.g., "cấp cứu", "nguy kịch", "cháy nhà", "khẩn cấp nhất", "sống còn", "emergency", "top priority").
2. "high": Urgent or highly important tasks (e.g., "gấp", "quan trọng", "ngay", "khẩn cấp", "urgent", "important", "ASAP", "must do").
3. "low": Chill, optional, or no-rush tasks (e.g., "rảnh", "từ từ", "không vội", "optional", "nếu được", "lúc nào cũng được").
4. "medium": Default for standard tasks without explicit urgency.

### OUTPUT SCHEMA (STRICT JSON ARRAY ONLY):
You MUST output a valid JSON array of objects. DO NOT wrap it in markdown formatting like \`\`\`json.
Each object MUST contain:
1. "name": A concise task title.
2. "scheduled_start": A strict ISO-8601 string INCLUDING THE TIMEZONE OFFSET (e.g., "2026-05-15T09:00:00${tzString}").
3. "scheduled_end": A strict ISO-8601 string INCLUDING THE TIMEZONE OFFSET.
4. "priority": MUST BE exactly "low", "medium", "high", or "critical".
5. "content_detail": (Optional) Quill Delta JSON ops array for extracted notes/context. Use an array like [{"insert":"Detail text\\n"}]. The document must end with a newline.

### EXAMPLE INPUT & OUTPUT:
Input: "Đưa mẹ đi cấp cứu ngay bây giờ, chiều mai 3h đi họp gấp, cuối tuần rảnh thì đi cafe"
Output:
[
  {
    "name": "Đưa mẹ đi cấp cứu",
    "scheduled_start": "${localIsoString}",
    "scheduled_end": "2026-05-15T13:09:00${tzString}",
    "priority": "critical",
    "content_detail": [{"insert":"Ngay bây giờ\\n"}]
  },
  {
    "name": "Họp gấp",
    "scheduled_start": "2026-05-16T15:00:00${tzString}",
    "scheduled_end": "2026-05-16T16:00:00${tzString}",
    "priority": "high",
    "content_detail": [{"insert":"Họp gấp\\n"}]
  },
  {
    "name": "Đi cafe",
    "scheduled_start": "2026-05-16T08:00:00${tzString}",
    "scheduled_end": "2026-05-16T09:00:00${tzString}",
    "priority": "low"
  }
]`;

  let aiTasks: AiTask[];
  try {
    let raw = await callVertexGemini(
      systemPrompt,
      body.text,
      'gemini-2.5-flash',
      2048,
    );
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();

    aiTasks = JSON.parse(raw);
    if (!Array.isArray(aiTasks)) throw new Error('AI response is not an array');
  } catch (err) {
    console.error('AI parsing error:', err);
    return jsonResponse({ error: 'Failed to parse natural language.' }, 500);
  }

  let tasksToInsert: Record<string, unknown>[];
  try {
    tasksToInsert = aiTasks.map((t) => ({
      user_id: user.id,
      name: t.name,
      scheduled_start: normalizeTimestampToUtcIso(
        t.scheduled_start,
        offsetMinutes,
      ),
      scheduled_end: normalizeTimestampToUtcIso(
        t.scheduled_end,
        offsetMinutes,
      ),
      task_type: 'manual_single',
      priority: t.priority ?? 'medium',
      status: 'pending',
    }));
  } catch (err) {
    console.error('AI schedule normalization error:', err);
    return jsonResponse({ error: 'Invalid generated schedule.' }, 500);
  }

  const { data: inserted, error: insertError } = await supabase
    .from('daily_task')
    .insert(tasksToInsert)
    .select();

  if (insertError) {
    console.error('Insert error:', insertError);
    return jsonResponse({ error: insertError.message }, 500);
  }

  const noteRows = (inserted ?? [])
    .map((task, index) => {
      const aiTask = aiTasks[index];
      if (!aiTask || !hasOwnKey(aiTask, 'content_detail')) {
        return null;
      }

      const contentDelta = normalizeQuillDelta(aiTask.content_detail);
      return {
        user_id: user.id,
        title: task.name ?? '',
        content_delta: contentDelta,
        plain_text: plainTextFromDelta(contentDelta),
        reference_type: 'task',
        reference_id: task.id,
        color: task.color ?? null,
      };
    })
    .filter((row): row is Record<string, unknown> => row !== null);

  let insertedNotes: unknown[] = [];
  if (noteRows.length > 0) {
    const { data: notes, error: noteInsertError } = await supabase
      .from('note')
      .insert(noteRows)
      .select();
    if (noteInsertError) {
      console.error('Note insert error:', noteInsertError);
      return jsonResponse({ error: noteInsertError.message }, 500);
    }
    insertedNotes = notes ?? [];
  }

  return jsonResponse({ tasks: inserted, notes: insertedNotes });
});
