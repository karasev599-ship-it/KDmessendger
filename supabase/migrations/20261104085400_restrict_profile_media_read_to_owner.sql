begin;

-- Profile media is stored under a first-level user UUID, matching the
-- existing INSERT, UPDATE and DELETE ownership rules. Do not let every
-- authenticated user read every private profile-media object.
drop policy if exists kd_profile_media_read on storage.objects;

create policy kd_profile_media_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'kd-profile-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

commit;
