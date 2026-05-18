import { corsHeaders, handleCors } from './cors.ts';

export function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function requirePost(req: Request): Response | null {
  const corsResponse = handleCors(req);
  if (corsResponse) {
    return corsResponse;
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  return null;
}

type ParseJsonResult<T> =
  | { ok: true; body: T }
  | { ok: false; response: Response };

export async function parseJsonBody<T>(
  req: Request,
): Promise<ParseJsonResult<T>> {
  try {
    return { ok: true, body: await req.json() as T };
  } catch {
    return {
      ok: false,
      response: jsonResponse({ error: 'Invalid JSON body' }, 400),
    };
  }
}
