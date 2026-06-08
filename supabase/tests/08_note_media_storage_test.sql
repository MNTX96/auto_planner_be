BEGIN;

SELECT plan(6);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM storage.buckets
    WHERE id = 'note_media'
      AND name = 'note_media'
      AND public = false
  ),
  'note_media bucket exists and is private'
);

SELECT is(
  (
    SELECT COUNT(*)::INTEGER
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname IN (
        'note_media_select_own',
        'note_media_insert_own',
        'note_media_update_own',
        'note_media_delete_own'
      )
  ),
  4,
  'note_media has SELECT/INSERT/UPDATE/DELETE storage policies'
);

SELECT like(
  (
    SELECT qual
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'note_media_select_own'
  ),
  '%bucket_id = ''note_media''%',
  'note_media SELECT policy is scoped to the bucket'
);

SELECT like(
  (
    SELECT with_check
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'note_media_insert_own'
  ),
  '%bucket_id = ''note_media''%',
  'note_media INSERT policy is scoped to the bucket'
);

SELECT like(
  lower(
    (
      SELECT with_check
      FROM pg_policies
      WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'note_media_insert_own'
    )
  ),
  '%storage.foldername%',
  'note_media INSERT policy checks the auth uid path prefix'
);

SELECT like(
  lower(
    (
      SELECT qual
      FROM pg_policies
      WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'note_media_delete_own'
    )
  ),
  '%storage.foldername%',
  'note_media DELETE policy checks the auth uid path prefix'
);

SELECT * FROM finish();
ROLLBACK;
