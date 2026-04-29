import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';

interface RegeneratePlanRequest {
  plan_id: string;
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

  let body: RegeneratePlanRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!body.plan_id?.trim()) {
    return new Response(JSON.stringify({ error: 'plan_id is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const supabase = getSupabaseClient(req);

  // RLS ensures the caller owns this plan — returns 404 if not found or unauthorized
  const { data: plan, error } = await supabase
    .from('plans')
    .select('domain, prompt_goal, prompt_current_status, prompt_available_time, prompt_constraints')
    .eq('id', body.plan_id)
    .single();

  if (error || !plan) {
    const status = error?.code === 'PGRST116' ? 404 : 500;
    return new Response(JSON.stringify({ error: error?.message ?? 'Plan not found' }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(plan), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
