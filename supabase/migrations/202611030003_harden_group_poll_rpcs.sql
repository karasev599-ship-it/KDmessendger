begin;

create or replace function public.kd_create_group_poll(
  p_conversation_id uuid,
  p_question text,
  p_options text[],
  p_multiple boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_poll uuid;
  v_message uuid;
  v_user uuid := auth.uid();
  v_option_count integer;
  v_distinct_count integer;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if not public.check_api_rate_limit('group_poll_create', md5(v_user::text), 60, 5) then
    raise exception 'Too many poll creation requests; try again later' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.kd_conversation_members
    where conversation_id = p_conversation_id and user_id = v_user
  ) then
    raise exception 'Not a group member' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.kd_conversations
    where id = p_conversation_id and kind = 'group'
  ) then
    raise exception 'Polls require an existing group' using errcode = '22023';
  end if;

  if p_question is null or length(btrim(p_question)) < 1 or length(btrim(p_question)) > 240 then
    raise exception 'Question must contain 1 to 240 characters' using errcode = '22023';
  end if;

  if p_options is null or cardinality(p_options) < 2 or cardinality(p_options) > 10 then
    raise exception 'A poll must have between 2 and 10 options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(p_options) as option_text
    where option_text is null
       or length(btrim(option_text)) < 1
       or length(btrim(option_text)) > 100
  ) then
    raise exception 'Each option must contain 1 to 100 characters' using errcode = '22023';
  end if;

  select count(*), count(distinct lower(btrim(option_text)))
    into v_option_count, v_distinct_count
  from unnest(p_options) as option_text;

  if v_option_count <> v_distinct_count then
    raise exception 'Poll options must be unique' using errcode = '22023';
  end if;

  insert into public.kd_messages(conversation_id, sender_id, body, message_type)
  values (p_conversation_id, v_user, '', 'poll')
  returning id into v_message;

  insert into public.kd_group_polls(
    conversation_id, created_by, question, multiple_choice, message_id
  )
  values (
    p_conversation_id, v_user, btrim(p_question), coalesce(p_multiple, false), v_message
  )
  returning id into v_poll;

  insert into public.kd_group_poll_options(poll_id, option_text, position)
  select v_poll, btrim(option_text), ordinality - 1
  from unnest(p_options) with ordinality as options(option_text, ordinality);

  return v_poll;
end;
$function$;

create or replace function public.kd_set_group_poll_votes(
  p_poll_id uuid,
  p_option_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := auth.uid();
  v_conversation_id uuid;
  v_closed boolean;
  v_multiple boolean;
  v_option_count integer;
  v_distinct_count integer;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if not public.check_api_rate_limit('group_poll_vote', md5(v_user::text), 60, 60) then
    raise exception 'Too many poll vote requests; try again later' using errcode = 'P0001';
  end if;

  p_option_ids := coalesce(p_option_ids, '{}'::uuid[]);

  if cardinality(p_option_ids) > 10 then
    raise exception 'A poll vote may contain at most 10 options' using errcode = '22023';
  end if;

  select count(*), count(distinct option_id)
    into v_option_count, v_distinct_count
  from unnest(p_option_ids) as option_id;

  if v_option_count <> v_distinct_count then
    raise exception 'Duplicate poll options are not allowed' using errcode = '22023';
  end if;

  select conversation_id, closed, multiple_choice
    into v_conversation_id, v_closed, v_multiple
  from public.kd_group_polls
  where id = p_poll_id
  for update;

  if v_conversation_id is null then
    raise exception 'Poll not found' using errcode = 'P0002';
  end if;

  if v_closed then
    raise exception 'Poll closed' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.kd_conversation_members
    where conversation_id = v_conversation_id and user_id = v_user
  ) then
    raise exception 'Not a member' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(p_option_ids) as option_id
    where not exists (
      select 1
      from public.kd_group_poll_options o
      where o.id = option_id and o.poll_id = p_poll_id
    )
  ) then
    raise exception 'Invalid poll option' using errcode = '22023';
  end if;

  if not v_multiple and cardinality(p_option_ids) > 1 then
    raise exception 'Single choice poll' using errcode = '22023';
  end if;

  delete from public.kd_group_poll_votes
  where poll_id = p_poll_id and user_id = v_user;

  insert into public.kd_group_poll_votes(poll_id, option_id, user_id)
  select p_poll_id, option_id, v_user
  from unnest(p_option_ids) as option_id;

  return true;
end;
$function$;

revoke all on function public.kd_create_group_poll(uuid, text, text[], boolean) from public, anon, authenticated;
grant execute on function public.kd_create_group_poll(uuid, text, text[], boolean) to authenticated;

revoke all on function public.kd_set_group_poll_votes(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.kd_set_group_poll_votes(uuid, uuid[]) to authenticated;

commit;
