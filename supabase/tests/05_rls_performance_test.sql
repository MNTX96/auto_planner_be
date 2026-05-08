-- Regression guard: ensure no RLS policy uses bare auth.uid() without (select ...) wrapper.
-- A bare call is re-evaluated per row; (select auth.uid()) is evaluated once per query.

BEGIN;
SELECT plan(2);

SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_policies
    WHERE schemaname = 'public'
      AND qual ~ 'auth\.(uid|jwt|role)\(\)'
      AND qual !~ '\(select auth\.'
  ),
  0,
  'No RLS USING clause has bare auth.uid() — all must use (select auth.uid())'
);

SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_policies
    WHERE schemaname = 'public'
      AND with_check ~ 'auth\.(uid|jwt|role)\(\)'
      AND with_check !~ '\(select auth\.'
  ),
  0,
  'No RLS WITH CHECK clause has bare auth.uid() — all must use (select auth.uid())'
);

SELECT * FROM finish();
ROLLBACK;
