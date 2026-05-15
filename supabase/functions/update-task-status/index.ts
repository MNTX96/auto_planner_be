import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';

type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'missed';

const VALID_STATUSES: TaskStatus[] = ['pending', 'in_progress', 'completed', 'missed'];

interface UpdateTaskStatusRequest {
  task_id: string;
  status: TaskStatus;
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

  let body: UpdateTaskStatusRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!body.task_id?.trim()) {
    return new Response(JSON.stringify({ error: 'task_id is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  if (!VALID_STATUSES.includes(body.status)) {
    return new Response(
      JSON.stringify({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  const supabase = getSupabaseClient(req);

  // Update task status — triggers handle completed_at and progress recalculation
  const { error: updateError } = await supabase
    .from('daily_task')
    .update({ status: body.status })
    .eq('id', body.task_id);

  if (updateError) {
    const status = updateError.code === 'PGRST116' ? 404 : 500;
    return new Response(JSON.stringify({ error: updateError.message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // Fetch updated task + parent milestone + plan progress for client optimistic update
  const { data: task, error: fetchError } = await supabase
    .from('daily_task')
    .select(`
      id,
      status,
      completed_at,
      milestone_id,
      milestone (
        id,
        progress_percentage,
        plan_id,
        plan (
          id,
          progress_percentage
        )
      )
    `)
    .eq('id', body.task_id)
    .single();

  if (fetchError || !task) {
    return new Response(JSON.stringify({ error: 'Task updated but could not fetch result' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const milestoneData = Array.isArray(task.milestone) ? task.milestone[0] : task.milestone;
  const planData = Array.isArray(milestoneData?.plan) ? milestoneData.plan[0] : milestoneData?.plan;

  return new Response(
    JSON.stringify({
      task_id: task.id,
      status: task.status,
      completed_at: task.completed_at,
      milestone_progress: milestoneData?.progress_percentage ?? 0,
      plan_progress: planData?.progress_percentage ?? 0,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});
