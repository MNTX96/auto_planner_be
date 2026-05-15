import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface CreateTaskAiRequest {
  text: string;
  timezone_offset_minutes?: number; 
}

interface AiTask {
  name: string;
  scheduled_start: string; 
  scheduled_end: string;   
  details?: string;
  priority: 'low' | 'medium' | 'high' | 'critical';
}

function formatTimezoneOffset(offsetMinutes: number): string {
  const sign = offsetMinutes >= 0 ? '+' : '-';
  const absOffset = Math.abs(offsetMinutes);
  const hours = String(Math.floor(absOffset / 60)).padStart(2, '0');
  const minutes = String(absOffset % 60).padStart(2, '0');
  return `${sign}${hours}:${minutes}`;
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  let body: CreateTaskAiRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!body.text?.trim()) {
    return new Response(JSON.stringify({ error: 'text is required' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const supabase = getSupabaseClient(req);

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const offsetMinutes = body.timezone_offset_minutes ?? 420; 
  const tzString = formatTimezoneOffset(offsetMinutes);
  
  const utcNow = new Date();
  const localNow = new Date(utcNow.getTime() + offsetMinutes * 60 * 1000);
  const localIsoString = localNow.toISOString().replace('Z', '') + tzString; 
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
5. "details": (Optional) Extracted notes or context.

### EXAMPLE INPUT & OUTPUT:
Input: "Đưa mẹ đi cấp cứu ngay bây giờ, chiều mai 3h đi họp gấp, cuối tuần rảnh thì đi cafe"
Output:
[
  {
    "name": "Đưa mẹ đi cấp cứu",
    "scheduled_start": "${localIsoString}",
    "scheduled_end": "2026-05-15T13:09:00${tzString}",
    "priority": "critical",
    "details": "Ngay bây giờ"
  },
  {
    "name": "Họp gấp",
    "scheduled_start": "2026-05-16T15:00:00${tzString}",
    "scheduled_end": "2026-05-16T16:00:00${tzString}",
    "priority": "high",
    "details": "Họp gấp"
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
    let raw = await callVertexGemini(systemPrompt, body.text, 'gemini-2.5-flash', 2048);
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
    
    aiTasks = JSON.parse(raw);
    if (!Array.isArray(aiTasks)) throw new Error('AI response is not an array');
  } catch (err) {
    console.error('AI parsing error:', err);
    return new Response(JSON.stringify({ error: 'Failed to parse natural language.' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const tasksToInsert = aiTasks.map((t) => ({
    user_id: user.id,
    name: t.name,
    details: t.details ?? null,
    scheduled_start: new Date(t.scheduled_start).toISOString(),
    scheduled_end: new Date(t.scheduled_end).toISOString(),
    task_type: 'manual_single',
    priority: t.priority ?? 'medium', 
    status: 'pending',
  }));

  const { data: inserted, error: insertError } = await supabase
    .from('daily_task')
    .insert(tasksToInsert)
    .select();

  if (insertError) {
    console.error('Insert error:', insertError);
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  return new Response(
    JSON.stringify({ tasks: inserted }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});
