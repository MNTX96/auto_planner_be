import { getSupabaseClient } from '../_shared/auth.ts';
import { jsonResponse, parseJsonBody, requirePost } from '../_shared/http.ts';
import { callVertexGemini, VertexPart, arrayBufferToBase64 } from '../_shared/vertex.ts';

interface AnalyzePromptRequest {
  prompt: string;
  files?: string[];
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
1. [Goal & Scope]: What is the exact objective? (e.g., "Lose 5kg" is acceptable, but "Get fit" is too vague).
2.[Context & Baseline]: What is the starting point? Who is involved?
3. [Resources & ABSOLUTE DATES]: What is the available capital? CRITICAL: Because this app schedules tasks on a real calendar, you MUST know the EXACT START DATE or DATE RANGE. If the user only says "for 3 days" without specifying WHEN to start, you MUST generate a "date_picker" or "date_range_picker" input to ask them.
4. [Constraints & Risks]: What are the hard boundaries? (Allergies, non-negotiable deadlines, preferences).

### SINGLE RESPONSIBILITY RULE FOR INPUTS (CRITICAL)
If you generate "required_inputs", each item in the array MUST ask for ONE and ONLY ONE specific piece of information. DO NOT combine multiple questions into a single input field.
- ❌ BAD: "What is your budget and travel dates?" (Combined)
- ✅ GOOD: Create 2 separate items: One for "Budget" (number_input) and one for "Travel Dates" (date_range_picker).

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
    "domain": "MUST BE EXACTLY ONE OF THESE ENGLISH WORDS:['Travel', 'Study', 'Fitness', 'Health', 'Food', 'Finance', 'Career', 'Event', 'Shopping', 'Home', 'Family', 'Hobby', 'Project', 'Pets', 'Lifestyle', 'Social', 'Content', 'Other']. Evaluate the prompt and pick the most suitable category. NEVER translate this word to the user's language.",
    "summary_goal": "Summary of what they want based on current input"
  },
  "required_inputs":[
    // Empty array [] if is_complete is true. Otherwise generate fields:
    {
      "id": "unique_id_string", 
      "title": "Short UI Label (Must focus on ONE specific information only)",
      "type": "MUST BE ONE OF THE STRICT ALLOWED INPUT TYPES",
      "pillar_category": "MUST BE ONE OF: 'Goal_Scope', 'Context', 'Resources', 'Constraints_Risks'", 
      "is_required": boolean, 
      "suggestion": "Placeholder text or helpful hint",
      "options":["Opt 1", "Opt 2"], // REQUIRED if type is "*_chips"
      "slider_min": 1, // REQUIRED if type is "slider"
      "slider_max": 10 // REQUIRED if type is "slider"
    }
  ]
}`;

Deno.serve(async (req: Request) => {
  const methodError = requirePost(req);
  if (methodError) return methodError;

  try {
    const supabase = getSupabaseClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    
    if (authError || !user) {
      return jsonResponse({ error: 'Not authenticated' }, 401);
    }

    const parsedBody = await parseJsonBody<AnalyzePromptRequest>(req);
    if (!parsedBody.ok) return parsedBody.response;
    const { body } = parsedBody;

    if (!body.prompt?.trim()) {
      return jsonResponse({ error: 'prompt is required' }, 400);
    }

    const { data: profile } = await supabase
      .from('profile')
      .select('locale, tier')
      .eq('id', user.id)
      .single();

    const language = localeToLanguage(profile?.locale ?? 'en');
    const tier = profile?.tier ?? 'free';

    const { data: config } = await supabase
      .from('ai_config')
      .select('model_name, max_output_tokens')
      .eq('tier', tier)
      .single();

    const modelName = config?.model_name ?? 'gemini-2.5-flash';
    const maxOutputTokens = config?.max_output_tokens ?? 2048;
    
    const systemPrompt =
      SYSTEM_PROMPT +
      `\n\n### LANGUAGE REQUIREMENT\nYou MUST write all user-facing text values in the JSON output (\`title\`, \`suggestion\`, \`options\` arrays, \`summary_goal\`) in ${language}. Do NOT translate system keys like \`type\`, \`pillar_category\`, or \`id\`.`;

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
    parts.push({ text: body.prompt });

    // Call AI (Vertex/Gemini)
    let raw = await callVertexGemini(systemPrompt, parts, modelName, maxOutputTokens);
    
    raw = raw.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
    const analysis = JSON.parse(raw);

    return jsonResponse(analysis);
  } catch (e) {
    console.error('analyze-prompt error:', e);
    return jsonResponse({ error: String(e) }, 500);
  }
});
