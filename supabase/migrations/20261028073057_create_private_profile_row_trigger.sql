begin;

-- New profiles receive a private row so phone search and legacy QR-token
-- resolution work from the first login, without exposing private columns.
create or replace function public.kd_create_private_profile_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.kd_profile_private (user_id, phone, phone_visible, qr_token, updated_at)
  values (new.id, new.phone, coalesce(new.phone_visible, false), new.qr_token, coalesce(new.updated_at, now()))
  on conflict (user_id) do nothing;
  return new;
end;
$function$;

revoke all on function public.kd_create_private_profile_row() from public, anon, authenticated;

drop trigger if exists kd_profiles_create_private_profile on public.kd_profiles;
create trigger kd_profiles_create_private_profile
after insert on public.kd_profiles
for each row execute function public.kd_create_private_profile_row();

commit;