import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini, VertexPart, arrayBufferToBase64 } from '../_shared/vertex.ts';

function localeToLanguage(locale: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'language' }).of(locale) ?? 'English';
  } catch {
    return 'English';
  }
}

// 1. Giao diện nhận data mới: Khớp với Dynamic UI
interface GeneratePlanRequest {
  original_prompt: string;
  answers: Record<string, any>; // Chứa các câu trả lời động (VD: { "budget": 5000, "date": "2024-10-10" })
  files?: string[];
}

const SYSTEM_PROMPT = `You are an expert planning assistant. Generate a detailed, actionable plan.

### INPUT CONTEXT:
You will receive a JSON payload containing:
1. "original_prompt": The user's initial idea.
2. "answers": Specific details, constraints, and preferences gathered from the user.
You MUST strictly obey all constraints provided in the "answers".

### OUTPUT SCHEMA (STRICT JSON ONLY, NO MARKDOWN):
{
  "prompt_goal": "Summary of the user's main goal",
  "domain": "MUST BE EXACTLY ONE OF THESE ENGLISH WORDS:['Travel', 'Study', 'Fitness', 'Health', 'Food', 'Finance', 'Career', 'Event', 'Shopping', 'Home', 'Family', 'Hobby', 'Project', 'Pets', 'Lifestyle', 'Social', 'Content', 'Other']. Evaluate the prompt and pick the most suitable category. NEVER translate this word to the user's language.",
  "title": "Concise plan title (max 60 chars)",
  "ultimate_goal": "Inspiring ultimate outcome statement",
  "total_duration": "Human-readable total duration (e.g., '3 days', '2 weeks')",
  "success_metrics": ["Measurable criterion 1", "Measurable criterion 2"],
  "expert_advice": {
    "tips": ["Actionable tip 1", "Actionable tip 2"],
    "warnings": ["Potential pitfall based on their constraints"]
  },
  "milestones": [
    {
      "milestone_index": 1,
      "name": "Phase/Day name (e.g., 'Day 1: Preparation')",
      "focus_objective": "Theme or focus for this milestone",
      "tasks": [
        {
          "task_index": 1,
          "name": "Specific actionable task name",
          "task_time": "Suggested time like '09:00 AM' or 'Anytime'",
          "duration_minutes": 30,
          "resources_or_location": "What you need or where to go",
          "details": "Brief instructions or tips for this task"
        }
      ]
    }
  ]
}

### RULES:
- Break the plan into logical milestones based on the timeframe in the "answers".
- Each milestone must have 2–6 concrete tasks.
- milestone_index starts at 1, task_index restarts at 1 per milestone.
- duration_minutes MUST be a positive integer ≥ 1. Never output 0 — use the best estimated value.
- Return ONLY the JSON object.`;

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

    if (!body.original_prompt?.trim()) {
      return new Response(JSON.stringify({ error: 'original_prompt is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('locale, tier')
      .eq('id', user.id)
      .single();

    const language = localeToLanguage(profile?.locale ?? 'en');
    const tier = profile?.tier ?? 'free';

    const { data: config } = await supabase
      .from('ai_configs')
      .select('model_name, max_output_tokens')
      .eq('tier', tier)
      .single();

    const modelName = config?.model_name ?? 'gemini-2.5-flash';
    const maxOutputTokens = config?.max_output_tokens ?? 8192;
    
    const systemPrompt =
      SYSTEM_PROMPT +
      `\n\n### LANGUAGE REQUIREMENT\nYou MUST write all text values in the JSON output in ${language}. Do not use any other language.`;

    // 2. Tự động đóng gói Input thành JSON để đưa cho AI
    const inputForAI = JSON.stringify({
      original_prompt: body.original_prompt,
      answers: body.answers ?? {}
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

    // 3. Gọi Gemini
    let raw = await callVertexGemini(systemPrompt, parts, modelName, maxOutputTokens);
    
    // 4. Clean up Markdown an toàn
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
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