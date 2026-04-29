-- Extends auth.users with public profile data
-- Rows are created exclusively by the handle_new_user trigger — no direct INSERT
CREATE TABLE profiles (
  id         UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name  TEXT,
  email      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
