interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const buffer = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buffer);
  for (let i = 0; i < binary.length; i++) {
    view[i] = binary.charCodeAt(i);
  }
  return buffer;
}

function base64UrlEncode(data: string | Uint8Array): string {
  const str = typeof data === 'string' ? data : String.fromCharCode(...data);
  return btoa(str).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function signJwt(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/cloud-platform',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export async function getVertexAccessToken(): Promise<{ token: string; projectId: string }> {
  const saBase64 = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  if (!saBase64) throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON is not set');

  const saJson = new TextDecoder().decode(Uint8Array.from(atob(saBase64), (c) => c.charCodeAt(0)));
  const sa: ServiceAccount = JSON.parse(saJson);
  const jwt = await signJwt(sa);

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Failed to get access token: ${err}`);
  }

  const data = await res.json();
  return { token: data.access_token as string, projectId: sa.project_id };
}

export interface VertexMessage {
  role: 'user' | 'model';
  parts: Array<{ text: string }>;
}

export async function callVertexGemini(
  systemInstruction: string,
  userMessage: string,
  model = 'gemini-2.0-flash-001',
  maxOutputTokens = 2048,
): Promise<string> {
  const location = Deno.env.get('VERTEX_AI_LOCATION') ?? 'us-central1';
  const { token, projectId } = await getVertexAccessToken();

  const endpoint =
    `https://${location}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${location}/publishers/google/models/${model}:generateContent`;

  const body = {
    systemInstruction: { parts: [{ text: systemInstruction }] },
    contents: [{ role: 'user', parts: [{ text: userMessage }] }],
    generationConfig: {
      maxOutputTokens,
      temperature: 0.7,
      responseMimeType: 'application/json',
    },
  };

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Vertex AI error ${res.status}: ${err}`);
  }

  const data = await res.json();
  const candidate = data.candidates?.[0];
  if (candidate?.finishReason === 'MAX_TOKENS') {
    throw new Error(`Vertex AI response was truncated (MAX_TOKENS). Increase maxOutputTokens.`);
  }
  const text: string = candidate?.content?.parts?.[0]?.text ?? '{}';
  return text;
}
