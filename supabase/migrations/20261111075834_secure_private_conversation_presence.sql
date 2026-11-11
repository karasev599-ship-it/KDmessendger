begin;

drop policy if exists kd_messenger_presence_receive on realtime.messages;
drop policy if exists kd_messenger_presence_send on realtime.messages;

create policy kd_messenger_presence_receive
on realtime.messages
for select
to authenticated
using (
  private is true
  and extension = 'presence'
  and realtime.topic() ~ '^kd-presence-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.kd_conversation_members m
    where m.conversation_id::text = substring(realtime.topic() from 13)
      and m.user_id = (select auth.uid())
  )
);

create policy kd_messenger_presence_send
on realtime.messages
for insert
to authenticated
with check (
  private is true
  and extension = 'presence'
  and realtime.topic() ~ '^kd-presence-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.kd_conversation_members m
    where m.conversation_id::text = substring(realtime.topic() from 13)
      and m.user_id = (select auth.uid())
  )
);

commit;
