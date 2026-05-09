import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface AnalyzePromptRequest {
  prompt: string;
}

function localeToLanguage(locale: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'language' }).of(locale) ?? 'English';
  } catch {
    return 'English';
  }
}

const SYSTEM_PROMPT = `You are an elite AI planning architect. Your task is to analyze the user's initial request. A perfect plan cannot be generated from vague or incomplete inputs.

### THE 4 CORE PILLARS & QUALITY CRITERIA
To set "is_complete" to true, the user's input MUST cover these 4 pillars, and the data MUST be Specific and Measurable:

1. [Goal & Scope]: What is the exact objective? (e.g., "Lose 5kg" is acceptable, but "Get fit" is too vague. Must clarify the success metric).
2.[Context & Baseline]: What is the starting point? Who is involved? (e.g., Solo trip or family? Beginner or advanced?).
3. [Resources]: What is the available capital? (This includes exact Available Time/Dates, Budget, and Tools/Equipment).
4. [Constraints & Risks]: What are the hard boundaries? (e.g., Allergies, injuries, non-negotiable deadlines, things they hate/want to avoid).

If the prompt is missing details in ANY of these 4 pillars, OR if the provided information is too vague/unmeasurable, you MUST generate "required_inputs" to clarify.

### STRICT ALLOWED INPUT TYPES (UI WIDGET SCOPE)
1. "text_input": General text answers.
2. "number_input": Numeric answers only (like budget, age, days).
3. "single_select_chips": Choose exactly ONE option.
4. "multi_select_chips": Choose MULTIPLE options.
5. "date_picker": Single specific date.
6. "date_range_picker": Start and end date.
7. "time_picker": Specific time of day.
8. "location_picker": City, place, or starting address.
9. "slider": Select a value within a range.
10. "switch": Yes/No or True/False.

### OUTPUT JSON SCHEMA REQUIREMENT
Return ONLY a valid JSON object with no markdown formatting.

{
  "is_complete": boolean, // true ONLY IF all 4 Pillars are fully satisfied AND are specific/measurable.
  "extracted_data": {
    "domain": "Travel, Fitness, Study, Project, etc.",
    "summary_goal": "Summary of what they want based on current input"
  },
  "required_inputs":[
    // Empty array [] if is_complete is true. Otherwise generate fields:
    {
      "id": "unique_id_string", 
      "title": "Short UI Label (e.g., 'Target Weight' or 'Budget Limit')",
      "type": "MUST BE ONE OF THE STRICT ALLOWED INPUT TYPES",
      "pillar_category": "MUST BE ONE OF: 'Goal_Scope', 'Context', 'Resources', 'Constraints_Risks'", 
      "is_required": boolean, // true if the plan CANNOT be made without this info. false if it's optional.
      "suggestion": "Placeholder text or helpful hint",
      "options":["Opt 1", "Opt 2"], // REQUIRED if type is "*_chips"
      "slider_min": 1, // REQUIRED if type is "slider"
      "slider_max": 10 // REQUIRED if type is "slider"
    }
  ]
}`;

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

    const { data: profile } = await supabase
      .from('profiles')
      .select('locale')
      .eq('id', user.id)
      .single();

    const language = localeToLanguage(profile?.locale ?? 'en');
    
    const systemPrompt =
      SYSTEM_PROMPT +
      `\n\n### LANGUAGE REQUIREMENT\nYou MUST write all user-facing text values in the JSON output (\`title\`, \`suggestion\`, \`options\` arrays, \`summary_goal\`) in ${language}. Do NOT translate system keys like \`type\`, \`pillar_category\`, or \`id\`.`;

    // Call AI (Vertex/Gemini)
    let raw = await callVertexGemini(systemPrompt, body.prompt, 'gemini-2.5-flash', 2048);
    
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
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
