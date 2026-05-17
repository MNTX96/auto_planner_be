-- Increase max_output_tokens for both tiers to handle large plan JSON responses.
-- Previous 8192 was causing MAX_TOKENS truncation on multi-milestone plans.
-- Gemini 2.5 Flash/Pro support up to 65535 output tokens.
UPDATE ai_config SET max_output_tokens = 32768 WHERE tier = 'free';
UPDATE ai_config SET max_output_tokens = 65535 WHERE tier = 'pro';
