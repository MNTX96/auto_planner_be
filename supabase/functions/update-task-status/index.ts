import { getSupabaseClient } from '../_shared/auth.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';

type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'missed';

const VALID_STATUSES: TaskStatus[] = [
  'pending',
  'in_progress',
  'completed',
  'missed',
];

interface UpdateTaskStatusRequest {
  task_id: string;
  status: TaskStatus;
}

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  const parsedBody = await parseJsonBody<UpdateTaskStatusRequest>(req);
  if (!parsedBody.ok) return parsedBody.response;
  const { body } = parsedBody;

  if (!body.task_id?.trim()) {
    return jsonResponse({ error: 'task_id is required' }, 400);
  }
  if (!VALID_STATUSES.includes(body.status)) {
    return jsonResponse(
      { error: `status must be one of: ${VALID_STATUSES.join(', ')}` },
      400,
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
    return jsonResponse({ error: updateError.message }, status);
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
    const status = fetchError?.code === 'PGRST116' ? 404 : 500;
    return jsonResponse(
      { error: fetchError?.message ?? 'Task updated but could not fetch result' },
      status,
    );
  }

  const milestoneData = Array.isArray(task.milestone)
    ? task.milestone[0]
    : task.milestone;
  const planData = Array.isArray(milestoneData?.plan)
    ? milestoneData.plan[0]
    : milestoneData?.plan;

  return jsonResponse({
    task_id: task.id,
    status: task.status,
    completed_at: task.completed_at,
    milestone_progress: milestoneData?.progress_percentage ?? 0,
    plan_progress: planData?.progress_percentage ?? 0,
  });
});
