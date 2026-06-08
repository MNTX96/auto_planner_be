import { getSupabaseClient } from '../_shared/auth.ts';
import {
  normalizeAppFlowyDocument,
  plainTextFromDocument,
} from '../_shared/appflowy_document.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';
import {
  formatTimezoneOffset,
  normalizeTimestampToUtcIso,
  toOffsetIsoString,
} from '../_shared/time.ts';
import {
  arrayBufferToBase64,
  callVertexGemini,
  VertexPart,
} from '../_shared/vertex.ts';
import pkg from 'npm:rrule';
const { rrulestr } = pkg;

function localeToLanguage(locale: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'language' }).of(locale) ??
      'English';
  } catch {
    return 'English';
  }
}

interface GeneratePlanRequest {
  original_prompt: string;
  answers: Record<string, unknown>;
  files?: string[];
  timezone_offset_minutes?: number;
}

interface AuthenticatedUser {
  id: string;
}

interface GeneratedTask {
  task_index?: unknown;
  name?: unknown;
  scheduled_start?: unknown;
  scheduled_end?: unknown;
  duration_minutes?: unknown;
  resources_or_location?: unknown;
  content_detail?: unknown;
}

interface GeneratedMilestone {
  milestone_index?: unknown;
  name?: unknown;
  focus_objective?: unknown;
  start_date?: unknown;
  end_date?: unknown;
  tasks?: unknown;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOwnKey(value: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
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

function textOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}

function numberOrNull(value: unknown): number | null {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string' && value.trim().length > 0
    ? Number(value)
    : Number.NaN;

  return Number.isFinite(parsed) ? parsed : null;
}

function positiveIntegerOrNull(value: unknown): number | null {
  const parsed = numberOrNull(value);
  if (parsed == null || parsed < 1) {
    return null;
  }
  return Math.round(parsed);
}

function indexOrFallback(value: unknown, fallback: number): number {
  const parsed = numberOrNull(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function generatedMilestones(
  plan: Record<string, unknown>,
): GeneratedMilestone[] {
  const milestones = plan.milestones;
  if (!Array.isArray(milestones)) {
    return [];
  }
  return milestones.filter(isRecord) as GeneratedMilestone[];
}

async function saveGeneratedPlan(
  supabase: ReturnType<typeof getSupabaseClient>,
  user: AuthenticatedUser,
  generatedPlan: Record<string, unknown>,
  request: GeneratePlanRequest,
  offsetMinutes: number,
): Promise<string> {
  let planId: string | null = null;
  const milestones = generatedMilestones(generatedPlan);
  if (milestones.length === 0) {
    throw new Error('Generated plan is missing valid milestones.');
  }

  try {
    const { data: plan, error: planError } = await supabase
      .from('plan')
      .insert({
        user_id: user.id,
        domain: textOrNull(generatedPlan.domain),
        original_prompt: request.original_prompt,
        answers: request.answers ?? {},
        prompt_goal: textOrNull(generatedPlan.prompt_goal),
        prompt_current_status: textOrNull(generatedPlan.prompt_current_status),
        prompt_available_time: textOrNull(generatedPlan.prompt_available_time),
        prompt_constraints: textOrNull(generatedPlan.prompt_constraints),
        title: textOrNull(generatedPlan.title),
        ultimate_goal: textOrNull(generatedPlan.ultimate_goal),
        total_duration: textOrNull(generatedPlan.total_duration),
        start_date: textOrNull(generatedPlan.start_date),
        end_date: textOrNull(generatedPlan.end_date),
        success_metrics: Array.isArray(generatedPlan.success_metrics)
          ? generatedPlan.success_metrics
          : [],
        expert_advice: isRecord(generatedPlan.expert_advice)
          ? generatedPlan.expert_advice
          : {},
      })
      .select('id')
      .single();

    if (planError) {
      throw planError;
    }
    if (!plan?.id) {
      throw new Error('Failed to insert generated plan.');
    }

    planId = plan.id as string;

    for (const [milestoneOffset, milestone] of milestones.entries()) {
      const { data: insertedMilestone, error: milestoneError } = await supabase
        .from('milestone')
        .insert({
          plan_id: planId,
          milestone_index: indexOrFallback(
            milestone.milestone_index,
            milestoneOffset + 1,
          ),
          name: textOrNull(milestone.name),
          focus_objective: textOrNull(milestone.focus_objective),
          start_date: textOrNull(milestone.start_date),
          end_date: textOrNull(milestone.end_date),
        })
        .select('id')
        .single();

      if (milestoneError) {
        throw milestoneError;
      }
      if (!insertedMilestone?.id) {
        throw new Error('Failed to insert generated milestone.');
      }

      const tasks = Array.isArray(milestone.tasks)
        ? milestone.tasks.filter(isRecord) as GeneratedTask[]
        : [];
      if (tasks.length === 0) {
        throw new Error('Generated milestone is missing tasks.');
      }

      const taskRows = tasks.map((task, taskOffset) => ({
        milestone_id: insertedMilestone.id,
        user_id: user.id,
        task_index: indexOrFallback(task.task_index, taskOffset + 1),
        name: textOrNull(task.name),
        scheduled_start: normalizeTimestampToUtcIso(
          task.scheduled_start,
          offsetMinutes,
        ),
        scheduled_end: normalizeTimestampToUtcIso(
          task.scheduled_end,
          offsetMinutes,
        ),
        duration_minutes: positiveIntegerOrNull(task.duration_minutes),
        resources_or_location: textOrNull(task.resources_or_location),
        task_type: 'ai_plan',
        status: 'pending',
      }));

      const { data: insertedTasks, error: taskError } = await supabase
        .from('daily_task')
        .insert(taskRows)
        .select('id,name,color');

      if (taskError) {
        throw taskError;
      }

      const noteRows = (insertedTasks ?? [])
        .map((task, taskOffset) => {
          const generatedTask = tasks[taskOffset];
          if (!generatedTask || !hasOwnKey(generatedTask, 'content_detail')) {
            return null;
          }

          const contentDocument = normalizeAppFlowyDocument(
            generatedTask.content_detail,
          );
          return {
            user_id: user.id,
            title: task.name ?? '',
            content_document: contentDocument,
            plain_text: plainTextFromDocument(contentDocument),
            reference_type: 'task',
            reference_id: task.id,
            color: task.color ?? null,
          };
        })
        .filter((row): row is Record<string, unknown> => row !== null);

      if (noteRows.length > 0) {
        const { error: noteError } = await supabase
          .from('note')
          .insert(noteRows);
        if (noteError) {
          throw noteError;
        }
      }
    }

    return planId;
  } catch (error) {
    if (planId != null) {
      const { error: cleanupError } = await supabase
        .from('plan')
        .delete()
        .eq('id', planId);
      if (cleanupError) {
        console.error(
          'Failed to clean up partially generated plan:',
          cleanupError,
        );
      }
    }
    throw error;
  }
}

function getSystemPrompt(
  currentDateTime: string,
  timezoneOffset: string,
  busyScheduleText: string,
  language: string,
): string {
  return `You are an elite AI planning architect. Generate a detailed, actionable, and conflict-free plan.

### CRITICAL TIME & SCHEDULING CONTEXT:
1. CURRENT LOCAL DATE & TIME: ${currentDateTime} (ISO-8601). Base all your scheduling calculations on this exact local moment unless the user specified a future date.
2. USER TIMEZONE OFFSET: ${timezoneOffset}. Interpret user-entered dates and times in this timezone.
3. USER'S EXISTING BUSY SCHEDULE:
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
          "scheduled_start": "YYYY-MM-DDTHH:mm:ss${timezoneOffset}",
          "scheduled_end": "YYYY-MM-DDTHH:mm:ss${timezoneOffset}",
          "duration_minutes": 30,
          "resources_or_location": "What you need or where to go",
          "content_detail": {"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Brief instructions or tips for this task"}]}}]}}
        }
      ]
    }
  ]
}

### RULES:
- CROSS-PLAN CONFLICT AVOIDANCE: You MUST NOT schedule any new tasks during the USER'S EXISTING BUSY SCHEDULE provided above. If a logical time overlaps with a busy block, find alternative free time.
- TIME FORMAT: "scheduled_start" and "scheduled_end" MUST be exact ISO-8601 timestamps with explicit timezone offset ${timezoneOffset}. The server will convert them to UTC before saving.
- Break the plan into logical milestones. Each milestone must have 2-6 concrete tasks.
- milestone_index starts at 1, task_index restarts at 1 per milestone.
- DIRECT LANGUAGE STRICTLY ENFORCED: Write directly to the point. NEVER use third-person narrator phrases. Start goals and tasks directly with action verbs.
- duration_minutes MUST be a positive integer >= 1. The mathematical difference between scheduled_start and scheduled_end MUST exactly match duration_minutes.
- NOTE CONTENT: "content_detail" is optional rich text for task notes. It MUST be an AppFlowy Editor document JSON object, such as {"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Text"}]}}]}}.
- Return ONLY the JSON object.

### LANGUAGE REQUIREMENT
You MUST write all user-facing text values in the JSON output (title, goal, metrics, tips, milestone name, task name, content_detail text) in ${language}. Do NOT translate system keys like domain.`;
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  try {
    const supabase = getSupabaseClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      return jsonResponse({ error: 'Not authenticated' }, 401);
    }

    const parsedBody = await parseJsonBody<GeneratePlanRequest>(req);
    if (!parsedBody.ok) return parsedBody.response;
    const { body } = parsedBody;

    if (!body.original_prompt?.trim()) {
      return jsonResponse({ error: 'original_prompt is required' }, 400);
    }

    const offsetMinutes = body.timezone_offset_minutes ?? 0;
    const timezoneOffset = formatTimezoneOffset(offsetMinutes);
    const now = new Date();
    const thirtyDaysLater = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const busyBlocks: string[] = [];

    const { data: existingTasks, error: taskError } = await supabase
      .from('daily_task')
      .select('name, scheduled_start, scheduled_end, rrule')
      .eq('user_id', user.id)
      .or(`scheduled_start.gte.${now.toISOString()},rrule.not.is.null`);

    if (taskError) {
      console.error('Failed to fetch existing tasks:', taskError);
    }

    if (existingTasks && existingTasks.length > 0) {
      for (const task of existingTasks) {
        if (!task.scheduled_start || !task.scheduled_end) {
          continue;
        }

        if (task.rrule) {
          try {
            const rule = rrulestr(task.rrule, {
              dtstart: new Date(task.scheduled_start),
            });
            const occurrences = rule.between(now, thirtyDaysLater, true);
            const durationMs = new Date(task.scheduled_end).getTime() -
              new Date(task.scheduled_start).getTime();

            for (const occDate of occurrences) {
              const occEndDate = new Date(occDate.getTime() + durationMs);
              busyBlocks.push(
                `- ${toOffsetIsoString(occDate, offsetMinutes)} to ${
                  toOffsetIsoString(occEndDate, offsetMinutes)
                }:[${task.name}]`,
              );
            }
          } catch (err) {
            console.error('RRULE parse error:', err);
          }
        } else {
          busyBlocks.push(
            `- ${
              toOffsetIsoString(new Date(task.scheduled_start), offsetMinutes)
            } to ${
              toOffsetIsoString(new Date(task.scheduled_end), offsetMinutes)
            }:[${task.name}]`,
          );
        }
      }
    }

    const busyScheduleText = busyBlocks.length > 0
      ? busyBlocks.join('\n')
      : "The user's schedule is completely free.";

    const { data: profile } = await supabase
      .from('profile')
      .select('locale, tier')
      .eq('id', user.id)
      .single();
    const language = localeToLanguage(profile?.locale ?? 'en');
    const tier = profile?.tier ?? 'free';

    const { data: config } = await supabase
      .from('ai_config')
      .select('model_name, max_output_tokens')
      .eq('tier', tier)
      .single();
    const modelName = config?.model_name ?? 'gemini-2.5-flash';
    const maxOutputTokens = config?.max_output_tokens ?? 32768;

    const currentDateTime = toOffsetIsoString(now, offsetMinutes);
    const systemPrompt = getSystemPrompt(
      currentDateTime,
      timezoneOffset,
      busyScheduleText,
      language,
    );

    const inputForAI = JSON.stringify({
      original_prompt: body.original_prompt,
      answers: body.answers ?? {},
    });

    const parts: VertexPart[] = [];
    if (body.files && body.files.length > 0) {
      for (const filePath of body.files) {
        const { data, error } = await supabase.storage
          .from('prompt_attachments')
          .download(filePath);
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

    let raw = await callVertexGemini(
      systemPrompt,
      parts,
      modelName,
      maxOutputTokens,
    );

    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
    const parsedPlanJson: unknown = JSON.parse(raw);
    if (!isRecord(parsedPlanJson)) {
      throw new Error('Generated plan is not a JSON object');
    }
    validateGeneratedPlan(parsedPlanJson);

    const planId = await saveGeneratedPlan(
      supabase,
      user,
      parsedPlanJson,
      body,
      offsetMinutes,
    );

    return jsonResponse({ plan_id: planId });
  } catch (e) {
    console.error('generate-plan error:', e);
    return jsonResponse({ error: String(e) }, 500);
  }
});
