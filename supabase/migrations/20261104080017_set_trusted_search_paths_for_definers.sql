begin;

-- Keep SECURITY DEFINER routines on a trusted search path. pg_catalog is
-- searched before the application schema so unqualified built-ins cannot
-- be shadowed by objects in public.
alter function public.kd_claim_e2ee_epoch(uuid)
  set search_path = pg_catalog, public;

alter function public.kd_get_my_suspension_status()
  set search_path = pg_catalog, public;

alter function public.kd_group_update_profile(uuid, text, text, text)
  set search_path = pg_catalog, public;

commit;
