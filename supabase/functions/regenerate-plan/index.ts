import { getSupabaseClient } from '../_shared/auth.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';

interface RegeneratePlanRequest {
  plan_id: string;
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<RegeneratePlanRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (!body.plan_id?.trim()) {
    return jsonResponse({ error: 'plan_id is required' }, 400);
  }

  const supabase = getSupabaseClient(req);

  // RLS ensures the caller owns this plan — returns 404 if not found or unauthorized
  const { data: plan, error } = await supabase
    .from('plan')
    .select('original_prompt, answers')
    .eq('id', body.plan_id)
    .single();

  if (error || !plan) {
    const status = error?.code === 'PGRST116' ? 404 : 500;
    return jsonResponse({ error: error?.message ?? 'Plan not found' }, status);
  }

  return jsonResponse(plan);
});
