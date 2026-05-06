import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface AnalyzePromptRequest {
  prompt: string;
}

const SYSTEM_PROMPT = `You are a planning assistant. Analyze the user's prompt and extract planning variables.

Extract these variables from the prompt if present:
- prompt_goal: The main goal or objective (REQUIRED)
- domain: Category like "travel", "fitness", "study", "work", "health", "personal", etc.
- prompt_current_status: Where the user is currently / starting point
- prompt_available_time: How much time they have (e.g., "3 days", "2 weeks", "1 month")
- prompt_constraints: Any limitations, budget, restrictions, or special conditions

Return a JSON object with this exact structure:
{
  "complete": <true if prompt_goal AND prompt_available_time are both present, otherwise false>,
  "missing": ["list of missing variable names from: prompt_goal, prompt_available_time"],
  "variables": {
    "prompt_goal": "...",
    "domain": "...",
    "prompt_current_status": "...",
    "prompt_available_time": "...",
    "prompt_constraints": "..."
  }
}

Include only variables that were explicitly mentioned or clearly implied in the prompt.
Return ONLY the JSON object, no markdown fences, no extra text.`;

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

    const body: AnalyzePromptRequest = await req.json();
    if (!body.prompt?.trim()) {
      return new Response(JSON.stringify({ error: 'prompt is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const raw = await callVertexGemini(SYSTEM_PROMPT, body.prompt, 'gemini-2.5-flash', 1024);
    const analysis = JSON.parse(raw);

    return new Response(JSON.stringify(analysis), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('analyze-prompt error:', e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
