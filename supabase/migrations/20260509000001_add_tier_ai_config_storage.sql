CREATE TYPE tier_type AS ENUM ('free', 'pro');

ALTER TABLE profiles ADD COLUMN tier tier_type NOT NULL DEFAULT 'free';

CREATE TABLE ai_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tier tier_type NOT NULL UNIQUE,
  model_name TEXT NOT NULL,
  max_output_tokens INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ai_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read access to authenticated users" ON ai_configs FOR SELECT TO authenticated USING (true);

INSERT INTO ai_configs (tier, model_name, max_output_tokens) VALUES
('free', 'gemini-2.5-flash', 8192),
('pro', 'gemini-2.5-pro', 8192);

-- Storage bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('prompt_attachments', 'prompt_attachments', false);

-- Storage policies
CREATE POLICY "Users can upload their own attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'prompt_attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can read their own attachments"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'prompt_attachments' AND (storage.foldername(name))[1] = auth.uid()::text);
