-- Add theme_mode and locale preferences to profiles table
-- theme_mode: 0=system, 1=light, 2=dark (matches Flutter ThemeMode enum index)
-- locale: language code e.g. 'en', 'vi'

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS theme_mode SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locale     TEXT      NOT NULL DEFAULT 'en';

COMMENT ON COLUMN profiles.theme_mode IS '0=system, 1=light, 2=dark (Flutter ThemeMode.index)';
COMMENT ON COLUMN profiles.locale IS 'BCP-47 language code, e.g. en, vi';
