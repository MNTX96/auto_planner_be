BEGIN;

SELECT plan(1);

SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_proc
    JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_proc.proname = 'save_plan_transaction'
  ),
  0,
  'save_plan_transaction RPC has been removed'
);

SELECT * FROM finish();

ROLLBACK;
