import { corsHeaders, handleCors } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/auth.ts';
import { callVertexGemini } from '../_shared/vertex.ts';

interface AnalyzePromptRequest {
  prompt: string;
}

const SYSTEM_PROMPT = `You are an elite AI planning architect. Your task is to analyze the user's initial request and determine if you have enough detailed information to generate a highly specific, realistic plan.

If the prompt is missing crucial context (like time, budget, constraints, or preferences), you must dynamically generate a list of required inputs for the frontend to render.

### STRICT ALLOWED INPUT TYPES (UI WIDGET SCOPE)
You MUST ONLY use the following string values for the "type" field. Do not invent new types:
1. "text_input": For general text answers.
2. "number_input": For numeric answers only (like budget, age, days).
3. "single_select_chips": For choosing exactly ONE option from a list.
4. "multi_select_chips": For choosing MULTIPLE options from a list (e.g., interests, dietary restrictions).
5. "date_picker": For a single specific date.
6. "date_range_picker": For a start and end date (highly recommended for travel or long projects).
7. "time_picker": For a specific time of day.
8. "location_picker": For finding a city, place, or starting address.
9. "slider": For selecting a value within a range (e.g., pace, intensity level).
10. "switch": For simple Yes/No or True/False boolean questions.

### OUTPUT JSON SCHEMA REQUIREMENT
Return ONLY a valid JSON object with no markdown formatting.

{
  "is_complete": boolean, // true ONLY IF you have all info to make a perfect plan. Otherwise, false.
  "extracted_data": {
    "domain": "Travel, Fitness, Study, etc.",
    "summary_goal": "Summary of what they want based on current input"
  },
  "required_inputs": [
    // Empty array [] if is_complete is true. Otherwise generate fields:
    {
      "id": "unique_id_string", 
      "title": "Short UI Label (e.g., 'Budget' or 'Travel Dates')",
      "type": "MUST BE ONE OF THE STRICT ALLOWED INPUT TYPES ABOVE",
      "suggestion": "Placeholder text or helpful hint",
      
      // CONDITIONAL FIELDS (Include only if relevant to the type):
      "options": ["Opt 1", "Opt 2", "Opt 3"], // REQUIRED if type is "*_chips"
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

    // Call AI (Vertex/Gemini)
    let raw = await callVertexGemini(SYSTEM_PROMPT, body.prompt, 'gemini-2.5-flash', 1024);
    
    // Safety check to strip markdown if Gemini accidentally adds ```json ... ```
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