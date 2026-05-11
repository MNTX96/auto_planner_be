import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini, VertexPart, arrayBufferToBase64 } from '../_shared/vertex.ts';
import pkg from 'npm:rrule';
const { rrulestr } = pkg;

function localeToLanguage(locale: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'language' }).of(locale) ?? 'English';
  } catch {
    return 'English';
  }
}

interface GeneratePlanRequest {
  original_prompt: string;
  answers: Record<string, any>;
  files?: string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validateGeneratedPlan(plan: Record<string, unknown>): void {
  if (typeof plan.prompt_goal !== 'string' || !plan.prompt_goal.trim()) {
    throw new Error('Generated plan is missing prompt_goal');
  }
  if (typeof plan.title !== 'string' || !plan.title.trim()) {
    throw new Error('Generated plan is missing title');
  }
  if (!Array.isArray(plan.milestones) || plan.milestones.length === 0) {
    throw new Error('Generated plan is missing milestones');
  }
}

function getSystemPrompt(currentDateTime: string, busyScheduleText: string, language: string): string {
  return `You are an elite AI planning architect. Generate a detailed, actionable, and conflict-free plan.

### CRITICAL TIME & SCHEDULING CONTEXT:
1. CURRENT DATE & TIME: ${currentDateTime} (ISO-8601). Base all your scheduling calculations on this exact moment unless the user specified a future date.
2. USER'S EXISTING BUSY SCHEDULE:
[START BUSY BLOCKS]
${busyScheduleText}
[END BUSY BLOCKS]

### INPUT CONTEXT:
You will receive a JSON payload containing:
1. "original_prompt": The user's initial idea.
2. "answers": Specific details, constraints, and dates gathered from the user.
You MUST strictly obey all constraints provided in the "answers".

### OUTPUT SCHEMA (STRICT JSON ONLY, NO MARKDOWN):
{
  "prompt_goal": "A direct, action-oriented statement of the goal. Start with a verb. DO NOT use narrator phrases. Example: 'Save $3000 in 6 months'",
  "domain": "MUST BE EXACTLY ONE OF THESE ENGLISH WORDS:['Travel', 'Study', 'Fitness', 'Health', 'Food', 'Finance', 'Career', 'Event', 'Shopping', 'Home', 'Family', 'Hobby', 'Project', 'Pets', 'Lifestyle', 'Social', 'Content', 'Other']. Evaluate the prompt and pick the most suitable category. NEVER translate this word.",
  "title": "Concise plan title (max 60 chars)",
  "ultimate_goal": "A direct, inspiring outcome statement.",
  "start_date": "YYYY-MM-DD",
  "end_date": "YYYY-MM-DD",
  "success_metrics":["Measurable criterion 1", "Measurable criterion 2"],
  "expert_advice": {
    "tips":["Actionable tip 1", "Actionable tip 2"],
    "warnings":["Potential pitfall based on constraints"]
  },
  "milestones":[
    {
      "milestone_index": 1,
      "name": "Phase/Day name (e.g., 'Day 1: Preparation')",
      "focus_objective": "Theme or focus for this milestone",
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD",
      "tasks":[
        {
          "task_index": 1,
          "name": "Specific actionable task name",
          "scheduled_start": "YYYY-MM-DDTHH:mm:ssZ",
          "scheduled_end": "YYYY-MM-DDTHH:mm:ssZ",
          "duration_minutes": 30,
          "resources_or_location": "What you need or where to go",
          "details": "Brief instructions or tips for this task"
        }
      ]
    }
  ]
}

### RULES:
- CROSS-PLAN CONFLICT AVOIDANCE: You MUST NOT schedule any new tasks during the USER'S EXISTING BUSY SCHEDULE provided above. If a logical time overlaps with a busy block, find alternative free time.
- TIME FORMAT: "scheduled_start" and "scheduled_end" MUST be exact ISO-8601 UTC timestamps.
- Break the plan into logical milestones. Each milestone must have 2-6 concrete tasks.
- milestone_index starts at 1, task_index restarts at 1 per milestone.
- DIRECT LANGUAGE STRICTLY ENFORCED: Write directly to the point. NEVER use third-person narrator phrases. Start goals and tasks directly with action verbs.
- duration_minutes MUST be a positive integer >= 1. The mathematical difference between scheduled_start and scheduled_end MUST exactly match duration_minutes.
- Return ONLY the JSON object.

### LANGUAGE REQUIREMENT
You MUST write all user-facing text values in the JSON output (title, goal, metrics, tips, milestone name, task name, details) in ${language}. Do NOT translate system keys like domain.`;
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const supabase = getSupabaseClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let body: GeneratePlanRequest;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!body.original_prompt?.trim()) {
      return new Response(JSON.stringify({ error: 'original_prompt is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const now = new Date();
    const thirtyDaysLater = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const busyBlocks: string[] =[];

    const { data: existingTasks, error: taskError } = await supabase
      .from('task')
      .select('name, scheduled_start, scheduled_end, rrule')
      .eq('user_id', user.id)
      .or(`scheduled_start.gte.${now.toISOString()},rrule.not.is.null`);

    if (taskError) {
      console.error('Failed to fetch existing tasks:', taskError);
    }

    if (existingTasks && existingTasks.length > 0) {
      existingTasks.forEach(t => {
        if (!t.scheduled_start || !t.scheduled_end) return;

        if (t.rrule) {
          try {
            const rule = rrulestr(t.rrule, { dtstart: new Date(t.scheduled_start) });
            const occurrences = rule.between(now, thirtyDaysLater, true);
            const durationMs = new Date(t.scheduled_end).getTime() - new Date(t.scheduled_start).getTime();

            occurrences.forEach(occDate => {
              const occEndDate = new Date(occDate.getTime() + durationMs);
              busyBlocks.push(`- ${occDate.toISOString()} to ${occEndDate.toISOString()}:[${t.name}]`);
            });
          } catch (err) {
            console.error('RRULE parse error:', err);
          }
        } else {
          busyBlocks.push(`- ${new Date(t.scheduled_start).toISOString()} to ${new Date(t.scheduled_end).toISOString()}:[${t.name}]`);
        }
      });
    }

    const busyScheduleText = busyBlocks.length > 0 
      ? busyBlocks.join('\n') 
      : "The user's schedule is completely free.";

    const { data: profile } = await supabase.from('profile').select('locale, tier').eq('id', user.id).single();
    const language = localeToLanguage(profile?.locale ?? 'en');
    const tier = profile?.tier ?? 'free';

    const { data: config } = await supabase.from('ai_config').select('model_name, max_output_tokens').eq('tier', tier).single();
    const modelName = config?.model_name ?? 'gemini-2.5-flash';
    const maxOutputTokens = config?.max_output_tokens ?? 8192;
    
    const currentDateTime = now.toISOString();
    const systemPrompt = getSystemPrompt(currentDateTime, busyScheduleText, language);

    const inputForAI = JSON.stringify({
      original_prompt: body.original_prompt,
      answers: body.answers ?? {},
    });

    const parts: VertexPart[] = [];
    if (body.files && body.files.length > 0) {
      for (const filePath of body.files) {
        const { data, error } = await supabase.storage.from('prompt_attachments').download(filePath);
        if (data) {
          const buffer = await data.arrayBuffer();
          const base64 = arrayBufferToBase64(buffer);
          parts.push({
            inlineData: {
              mimeType: data.type,
              data: base64,
            },
          });
        } else {
          console.error(`Failed to download ${filePath}:`, error);
        }
      }
    }
    parts.push({ text: inputForAI });

    let raw = await callVertexGemini(systemPrompt, parts, modelName, maxOutputTokens);
    
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
    const parsedPlanJson: unknown = JSON.parse(raw);
    if (!isRecord(parsedPlanJson)) {
      throw new Error('Generated plan is not a JSON object');
    }
    validateGeneratedPlan(parsedPlanJson);

    const payload = {
      ...parsedPlanJson,
      original_prompt: body.original_prompt,
      answers: body.answers ?? {},
    };

    const { data: planId, error: saveError } = await supabase.rpc(
      'save_plan_transaction',
      { payload },
    );

    if (saveError) {
      const status = saveError.message === 'Not authenticated' ? 401 : 500;
      return new Response(JSON.stringify({ error: saveError.message }), {
        status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!planId) {
      throw new Error('save_plan_transaction did not return a plan_id');
    }

    return new Response(JSON.stringify({ plan_id: planId }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('generate-plan error:', e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
