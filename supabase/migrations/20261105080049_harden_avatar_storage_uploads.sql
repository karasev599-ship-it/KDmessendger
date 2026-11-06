begin;

-- Group avatars are public assets, but only current group owners/admins may
-- upload into that group's namespace. Expected object path:
-- groups/<conversation_uuid>/<filename>
drop policy if exists kd_group_avatar_auth_insert on storage.objects;

create policy kd_group_avatar_auth_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'kd-messenger-avatars'
    and (storage.foldername(name))[1] = 'groups'
    and exists (
      select 1
      from public.kd_conversation_members cm
      join public.kd_conversations c
        on c.id = cm.conversation_id
      where cm.conversation_id = case
        when coalesce((storage.foldername(name))[2], '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (storage.foldername(name))[2]::uuid
        else null::uuid
      end
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
        and c.kind = 'group'
    )
  );

-- Public avatar buckets must not accept arbitrary file types or unbounded
-- uploads. SVG is deliberately excluded to avoid active-content uploads.
update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array[
         'image/jpeg',
         'image/png',
         'image/webp',
         'image/gif',
         'image/avif',
         'image/heic',
         'image/heif'
       ]::text[]
 where id in ('kd-messenger-avatars', 'kd-profile-avatars');

commit;
