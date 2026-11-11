begin;

drop policy if exists kd_messenger_call_receive on realtime.messages;
drop policy if exists kd_messenger_call_send on realtime.messages;
drop policy if exists kd_messenger_call_inbox_receive on realtime.messages;
drop policy if exists kd_messenger_call_inbox_send on realtime.messages;

create policy kd_messenger_call_receive
on realtime.messages
for select
to authenticated
using (
  private is true
  and extension = 'broadcast'
  and realtime.topic() ~ '^kd-call-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.kd_conversation_members m
    join public.kd_conversations c on c.id = m.conversation_id
    where m.conversation_id::text = substring(realtime.topic() from 9)
      and m.user_id = (select auth.uid())
      and c.kind = 'direct'
  )
);

create policy kd_messenger_call_send
on realtime.messages
for insert
to authenticated
with check (
  private is true
  and extension = 'broadcast'
  and realtime.topic() ~ '^kd-call-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and coalesce(payload->>'from', '') = (select auth.uid())::text
  and coalesce(payload->>'conversationId', '') = substring(realtime.topic() from 9)
  and coalesce(payload->>'callId', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.kd_conversation_members m
    join public.kd_conversations c on c.id = m.conversation_id
    where m.conversation_id::text = substring(realtime.topic() from 9)
      and m.user_id = (select auth.uid())
      and c.kind = 'direct'
  )
);

create policy kd_messenger_call_inbox_receive
on realtime.messages
for select
to authenticated
using (
  private is true
  and extension = 'broadcast'
  and realtime.topic() ~ '^kd-call-inbox-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and substring(realtime.topic() from 15) = (select auth.uid())::text
);

create policy kd_messenger_call_inbox_send
on realtime.messages
for insert
to authenticated
with check (
  private is true
  and extension = 'broadcast'
  and realtime.topic() ~ '^kd-call-inbox-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and coalesce(payload->>'from', '') = (select auth.uid())::text
  and coalesce(payload->>'to', '') = substring(realtime.topic() from 15)
  and coalesce(payload->>'callId', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.kd_conversation_members caller
    join public.kd_conversation_members recipient
      on recipient.conversation_id = caller.conversation_id
    join public.kd_conversations c on c.id = caller.conversation_id
    where caller.user_id = (select auth.uid())
      and recipient.user_id::text = substring(realtime.topic() from 15)
      and recipient.user_id <> caller.user_id
      and c.kind = 'direct'
      and caller.conversation_id::text = coalesce(payload->>'conversationId', '')
  )
);

commit;
