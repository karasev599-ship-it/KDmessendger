begin;

drop policy if exists kd_messenger_media_delete on storage.objects;

create policy kd_messenger_media_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'kd-messenger'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and cardinality(string_to_array(name, '/')) = 3
  and exists (
    select 1
    from public.kd_conversation_members cm
    where cm.conversation_id = case
      when split_part(objects.name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(objects.name, '/', 1)::uuid
      else null::uuid
    end
      and cm.user_id = (select auth.uid())
  )
);

commit;
