begin;

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

  p_option_ids := coalesce(p_option_ids, '{}'::uuid[]);

  if cardinality(p_option_ids) > 10 then
    raise exception 'A poll vote may contain at most 10 options' using errcode = '22023';
  end if;

  select count(*), count(distinct option_id)
    into v_option_count, v_distinct_count
  from unnest(p_option_ids) as options(option_id);

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
    from unnest(p_option_ids) as options(option_id)
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

  if not public.check_api_rate_limit('group_poll_vote', md5(v_user::text), 60, 60) then
    raise exception 'Too many poll vote requests; try again later' using errcode = 'P0001';
  end if;

  delete from public.kd_group_poll_votes
  where poll_id = p_poll_id and user_id = v_user;

  insert into public.kd_group_poll_votes(poll_id, option_id, user_id)
  select p_poll_id, option_id, v_user
  from unnest(p_option_ids) as options(option_id);

  return true;
end;
$function$;

revoke all on function public.kd_set_group_poll_votes(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.kd_set_group_poll_votes(uuid, uuid[]) to authenticated;

commit;
