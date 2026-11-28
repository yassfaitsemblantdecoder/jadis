-- Run on an isolated instance for synthetic tests, before allowing client traffic.
-- This script changes client privileges. It does not move or erase data.
begin;
set local search_path = pg_catalog;

do $pilot$
declare
  legacy_tables constant regclass[] := array[
    'public.schools'::regclass,
    'public.classes'::regclass,
    'public.memberships'::regclass,
    'public.teacher_notes'::regclass,
    'public.journeys'::regclass,
    'public.beta_school_entries'::regclass,
    'jadis_private.timeline_entries'::regclass,
    'jadis_private.search_notices'::regclass,
    'jadis_private.capsules'::regclass,
    'jadis_private.capsule_members'::regclass,
    'jadis_private.capsule_memories'::regclass,
    'jadis_private.capsule_photos'::regclass
  ];
  disabled_functions constant regprocedure[] := array[
    'public.beta_discover()'::regprocedure,
    'jadis_private.discover()'::regprocedure,
    'public.beta_timeline(text,uuid,jsonb)'::regprocedure,
    'jadis_private.timeline(text,uuid,jsonb)'::regprocedure,
    'public.beta_timeline_crossings(uuid,integer)'::regprocedure,
    'jadis_private.timeline_crossings(uuid,integer)'::regprocedure,
    'public.beta_search_notices(text,uuid,uuid,integer)'::regprocedure,
    'jadis_private.search_notices(text,uuid,uuid,integer)'::regprocedure,
    'public.beta_capsules(text,uuid,jsonb)'::regprocedure,
    'jadis_private.memory_capsules(text,uuid,jsonb)'::regprocedure,
    'public.beta_capsule_photos(text,uuid,jsonb)'::regprocedure,
    'jadis_private.capsule_photos(text,uuid,jsonb)'::regprocedure
  ];
  restricted_table regclass;
  disabled_function regprocedure;
  has_rows boolean;
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'beta_pilot_school'
      and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute')
  ) then
    raise exception 'Activation refusée : le RPC beta_pilot_school doit être accessible au rôle authenticated';
  end if;

  -- The precondition and the privilege changes belong to the same transaction.
  execute format('lock table %s in access exclusive mode', array_to_string(legacy_tables, ', '));
  foreach restricted_table in array legacy_tables loop
    execute format('select exists (select 1 from %s)', restricted_table) into has_rows;
    if has_rows then
      raise exception 'Activation refusée : données hors périmètre dans %', restricted_table;
    end if;
  end loop;

  foreach restricted_table in array legacy_tables loop
    execute format('revoke all privileges on table %s from public, anon, authenticated', restricted_table);
    -- Inherited role grants or explicit column grants must also fail closed.
    if exists (
      select 1 from unnest(array['anon','authenticated']) as clients(role_name)
      where has_table_privilege(clients.role_name, restricted_table,
              'select,insert,update,delete,truncate,references,trigger')
         or has_any_column_privilege(clients.role_name, restricted_table, 'select,insert,update,references')
    ) then
      raise exception 'Activation refusée : accès client résiduel à %', restricted_table;
    end if;
  end loop;

  -- Keep the private schema and internal helpers available to the retained RPCs.
  foreach disabled_function in array disabled_functions loop
    execute format('revoke all privileges on function %s from public, anon, authenticated', disabled_function);
    if has_function_privilege('anon', disabled_function, 'execute')
       or has_function_privilege('authenticated', disabled_function, 'execute') then
      raise exception 'Activation refusée : exécution client résiduelle de %', disabled_function;
    end if;
  end loop;
end;
$pilot$;

commit;
