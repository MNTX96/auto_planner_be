# Backend Deployment Secrets

Calendar sync Edge Functions require Supabase project secrets at deploy time.
Do not commit real secret values to git.

## Calendar Sync Secrets

| Secret | Required | Used by | Notes |
| --- | --- | --- | --- |
| `CALENDAR_TOKEN_ENCRYPTION_KEY` | Yes | `_shared/calendar_crypto.ts` | Encrypts and decrypts stored OAuth tokens. Keep stable after production launch. |
| `GOOGLE_WEB_CLIENT_ID` | Yes | `_shared/calendar_provider.ts` | Google OAuth token exchange and refresh client ID. |
| `GOOGLE_CALENDAR_CLIENT_SECRET` | Yes | `_shared/calendar_provider.ts` | Canonical Google client secret for calendar OAuth. |
| `GOOGLE_WEB_CLIENT_SECRET` | Legacy alias | `_shared/calendar_provider.ts` | Supported fallback only. Prefer `GOOGLE_CALENDAR_CLIENT_SECRET`. |
| `MICROSOFT_CLIENT_ID` | Yes | `_shared/calendar_provider.ts` | Microsoft OAuth app client ID. |
| `MICROSOFT_CLIENT_SECRET` | Optional | `_shared/calendar_provider.ts` | Include for confidential Microsoft app flows. Mobile PKCE can run without it. |
| `MICROSOFT_REDIRECT_URI` | Optional | `_shared/calendar_provider.ts` | Required only when the request does not provide `redirect_uri`. Mobile currently sends it. |

General Supabase Edge Function secrets are still required separately:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`.

## Verify Existing Secret Names

Check names only. Do not print or paste secret values:

```sh
supabase secrets list --project-ref <project-ref>
```

The deployed project should include at least:

```text
CALENDAR_TOKEN_ENCRYPTION_KEY
GOOGLE_WEB_CLIENT_ID
GOOGLE_CALENDAR_CLIENT_SECRET
MICROSOFT_CLIENT_ID
```

If the project already has `GOOGLE_WEB_CLIENT_SECRET`, keep it only as a
temporary fallback and add `GOOGLE_CALENDAR_CLIENT_SECRET` before deploying new
calendar sync functions.

## Set Required Secrets

```sh
supabase secrets set \
  CALENDAR_TOKEN_ENCRYPTION_KEY='<strong-random-value>' \
  GOOGLE_WEB_CLIENT_ID='<google-web-client-id>' \
  GOOGLE_CALENDAR_CLIENT_SECRET='<google-client-secret>' \
  MICROSOFT_CLIENT_ID='<microsoft-client-id>' \
  --project-ref <project-ref>
```

Set optional Microsoft secrets only when the target OAuth app needs them:

```sh
supabase secrets set \
  MICROSOFT_CLIENT_SECRET='<microsoft-client-secret>' \
  MICROSOFT_REDIRECT_URI='<redirect-uri>' \
  --project-ref <project-ref>
```

## Pre-Deploy Checklist

1. Verify the secret names with `supabase secrets list`.
2. Run Supabase function checks from `auto_planner_backend/supabase/functions`.
3. Run backend DB tests when schema or RLS changes are included.
4. Deploy functions only after the required names exist in the target project.
