import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface GeneratePlanRequest {
  variables: {
    prompt_goal: string;
    domain?: string;
    prompt_current_status?: string;
    prompt_available_time?: string;
    prompt_constraints?: string;
    [key: string]: string | undefined;
  };
  user_id?: string; // ignored — user identity comes from auth JWT
}

const SYSTEM_PROMPT = `You are an expert planning assistant. Generate a detailed, actionable plan.

Return a JSON object with this EXACT structure (no markdown, no extra text):
{
  "prompt_goal": "the user's main goal",
  "domain": "category of the plan",
  "prompt_current_status": "current status if provided",
  "prompt_available_time": "available time if provided",
  "prompt_constraints": "constraints if provided",
  "title": "concise plan title (max 60 chars)",
  "ultimate_goal": "inspiring ultimate outcome statement",
  "total_duration": "human-readable total duration (e.g. '3 days', '2 weeks')",
  "success_metrics": ["measurable success criterion 1", "measurable success criterion 2", "measurable success criterion 3"],
  "expert_advice": {
    "tips": ["actionable tip 1", "actionable tip 2", "actionable tip 3"],
    "warnings": ["potential pitfall 1", "potential pitfall 2"]
  },
  "milestones": [
    {
      "milestone_index": 1,
      "name": "Phase/Day name (e.g. 'Day 1: Preparation')",
      "focus_objective": "theme or focus for this milestone",
      "tasks": [
        {
          "task_index": 1,
          "name": "specific actionable task name",
          "task_time": "suggested time like '09:00 AM'",
          "duration_minutes": 30,
          "resources_or_location": "what you need or where to go",
          "details": "brief instructions or tips for this task"
        }
      ]
    }
  ]
}

Rules:
- Break the plan into logical milestones based on the available time
- Each milestone must have 3–6 concrete tasks
- milestone_index starts at 1, task_index restarts at 1 per milestone
- Be specific and actionable
- Return ONLY the JSON object`;

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const supabase = getSupabaseClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body: GeneratePlanRequest = await req.json();
    const vars = body.variables ?? {};

    if (!vars.prompt_goal?.trim()) {
      return new Response(JSON.stringify({ error: 'variables.prompt_goal is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const contextLines = [
      `Goal: ${vars.prompt_goal}`,
      vars.domain ? `Domain: ${vars.domain}` : null,
      vars.prompt_current_status ? `Current status: ${vars.prompt_current_status}` : null,
      vars.prompt_available_time ? `Available time: ${vars.prompt_available_time}` : null,
      vars.prompt_constraints ? `Constraints: ${vars.prompt_constraints}` : null,
    ].filter(Boolean).join('\n');

    const raw = await callVertexGemini(SYSTEM_PROMPT, contextLines, 'gemini-2.0-flash-001', 4096);
    const planJson = JSON.parse(raw);

    return new Response(JSON.stringify(planJson), {
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
