-- Prevent infinite RLS recursion on kd_conversation_members.
-- The membership check runs as a narrowly scoped SECURITY DEFINER function,
-- and policies still require the current authenticated user to be a member.

begin;

create or replace function public.kd_is_conversation_member(
  p_conversation_id uuid,
  p_user_id uuid,
  p_roles text[] default null
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_user_id = auth.uid()
    and exists (
      select 1
      from public.kd_conversation_members cm
      where cm.conversation_id = p_conversation_id
        and cm.user_id = auth.uid()
        and (p_roles is null or cm.role = any(p_roles))
    );
$$;

revoke all on function public.kd_is_conversation_member(uuid, uuid, text[]) from public;
grant execute on function public.kd_is_conversation_member(uuid, uuid, text[]) to authenticated;

drop policy if exists kd_member_select on public.kd_conversation_members;
create policy kd_member_select
on public.kd_conversation_members
for select to authenticated
using (public.kd_is_conversation_member(conversation_id, auth.uid(), null));

drop policy if exists kd_member_insert on public.kd_conversation_members;
create policy kd_member_insert
on public.kd_conversation_members
for insert to authenticated
with check (
  (
    user_id = auth.uid()
    and role = 'owner'
    and exists (
      select 1 from public.kd_conversations c
      where c.id = conversation_id and c.created_by = auth.uid()
    )
  )
  or
  (
    user_id <> auth.uid()
    and role = any(array['member', 'admin']::text[])
    and exists (
      select 1 from public.kd_conversations c
      where c.id = conversation_id
        and c.kind = 'group'
        and public.kd_is_conversation_member(c.id, auth.uid(), array['owner', 'admin']::text[])
    )
  )
);

commit;
