import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';

interface TaskInput {
  task_index: number;
  task_time?: string;
  name: string;
  duration_minutes?: number;
  resources_or_location?: string;
  details?: string;
}

interface MilestoneInput {
  milestone_index: number;
  name: string;
  focus_objective?: string;
  tasks: TaskInput[];
}

interface SavePlanRequest {
  domain?: string;
  prompt_goal: string;
  prompt_current_status?: string;
  prompt_available_time?: string;
  prompt_constraints?: string;
  title: string;
  ultimate_goal?: string;
  total_duration?: string;
  success_metrics?: string[];
  expert_advice?: Record<string, unknown>;
  milestones: MilestoneInput[];
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

  let body: SavePlanRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!body.prompt_goal?.trim()) {
    return new Response(JSON.stringify({ error: 'prompt_goal is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  if (!body.title?.trim()) {
    return new Response(JSON.stringify({ error: 'title is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  if (!Array.isArray(body.milestones) || body.milestones.length === 0) {
    return new Response(JSON.stringify({ error: 'milestones array is required and must not be empty' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const supabase = getSupabaseClient(req);

  const { data, error } = await supabase.rpc('save_plan_transaction', { payload: body });

  if (error) {
    const status = error.message === 'Not authenticated' ? 401 : 500;
    return new Response(JSON.stringify({ error: error.message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ plan_id: data }), {
    status: 201,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
