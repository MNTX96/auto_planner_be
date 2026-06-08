-- Private media bucket for AppFlowy note image blocks.
-- Objects are namespaced by auth.uid(): <user_id>/images/<file_name>.

INSERT INTO storage.buckets (id, name, public)
VALUES ('note_media', 'note_media', false)
ON CONFLICT (id) DO UPDATE
SET public = false;

DROP POLICY IF EXISTS "note_media_select_own"
  ON storage.objects;
CREATE POLICY "note_media_select_own"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'note_media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  );

DROP POLICY IF EXISTS "note_media_insert_own"
  ON storage.objects;
CREATE POLICY "note_media_insert_own"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'note_media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  );

DROP POLICY IF EXISTS "note_media_update_own"
  ON storage.objects;
CREATE POLICY "note_media_update_own"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'note_media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  )
  WITH CHECK (
    bucket_id = 'note_media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  );

DROP POLICY IF EXISTS "note_media_delete_own"
  ON storage.objects;
CREATE POLICY "note_media_delete_own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'note_media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  );

NOTIFY pgrst, 'reload schema';
