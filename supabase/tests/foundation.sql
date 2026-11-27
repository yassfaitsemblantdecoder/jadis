begin;

insert into auth.users (id, email_confirmed_at)
select ('00000000-0000-4000-8000-00000000000' || n)::uuid, now()
from generate_series(1, 4) as n;

insert into public.beta_members (user_id)
select id from auth.users where id <> '00000000-0000-4000-8000-000000000004';

insert into public.profiles (id, display_name, discoverable)
select user_id, 'Personne fictive ' || right(user_id::text, 1), true from public.beta_members;

insert into public.beta_school_entries (user_id, directory_id, school_name, year)
select id,
       case when right(id::text, 1) = '3' then 'fixture-other' else 'fixture-shared' end,
       'Établissement fictif', 2008
from public.profiles;

insert into jadis_private.institutions (id, name, kind) values
  ('10000000-0000-4000-8000-000000000001', 'Établissement fictif A', 'middle'),
  ('10000000-0000-4000-8000-000000000002', 'Établissement fictif B', 'middle');

insert into jadis_private.cohorts (id, institution_id, academic_year, level)
values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 2008, '3e');

insert into jadis_private.attendance (user_id, institution_id, academic_year)
values ('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 2008);

insert into jadis_private.attendance (user_id, institution_id, academic_year, cohort_id)
values ('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 2008,
        '20000000-0000-4000-8000-000000000001');

do $$
begin
  if has_table_privilege('anon', 'public.beta_school_entries', 'select')
     or has_function_privilege('anon', 'public.beta_discover()', 'execute') then
    raise exception 'Anonymous role has beta privileges';
  end if;

  if exists (
    select 1
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'jadis_private'
      and c.relname in ('institutions', 'institution_identifiers', 'institution_names', 'cohorts', 'attendance')
      and (not c.relrowsecurity
        or has_table_privilege('anon', c.oid, 'select,insert,update,delete')
        or has_table_privilege('authenticated', c.oid, 'select,insert,update,delete'))
  ) then
    raise exception 'Canonical tables lack RLS or grant direct client access';
  end if;

  begin
    insert into jadis_private.attendance (user_id, institution_id, academic_year)
    values ('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 2008);
    raise exception 'Duplicate attendance without cohort was accepted';
  exception when unique_violation then
    null;
  end;

  begin
    insert into jadis_private.attendance (user_id, institution_id, academic_year, cohort_id)
    values ('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 2008,
            '20000000-0000-4000-8000-000000000001');
    raise exception 'Cohort from a different institution was accepted';
  exception when foreign_key_violation then
    null;
  end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$
begin
  if exists (select 1 from public.beta_school_entries) or exists (select 1 from public.beta_discover()) then
    raise exception 'Non-member could read beta data';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$
declare
  matched_people uuid[];
begin
  if (select count(*) from public.beta_school_entries) <> 1
     or not exists (select 1 from public.beta_school_entries where user_id = auth.uid()) then
    raise exception 'Owner visibility on beta entries is incorrect';
  end if;

  select array_agg(person_id order by person_id) into matched_people from public.beta_discover();
  if matched_people is distinct from array['00000000-0000-4000-8000-000000000002'::uuid] then
    raise exception 'Discovery did not return only the consenting matched member';
  end if;
end $$;

reset role;
update public.profiles set discoverable = false where id = '00000000-0000-4000-8000-000000000002';
delete from jadis_private.discovery_limits;

set local role authenticated;
do $$
begin
  if exists (select 1 from public.beta_discover()) then
    raise exception 'Non-discoverable member appeared in matching';
  end if;
end $$;

reset role;
update public.profiles set discoverable = true where id = '00000000-0000-4000-8000-000000000002';
insert into public.blocks (owner, target)
values ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001');
delete from jadis_private.discovery_limits;

set local role authenticated;
do $$
begin
  if exists (select 1 from public.beta_discover()) then
    raise exception 'Incoming block did not exclude the match';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
do $$
begin
  if exists (select 1 from public.beta_discover()) then
    raise exception 'Outgoing block did not exclude the match';
  end if;
end $$;

reset role;
delete from auth.users where id = '00000000-0000-4000-8000-000000000001';
do $$
begin
  if exists (select 1 from jadis_private.attendance)
     or exists (select 1 from public.beta_school_entries where user_id = '00000000-0000-4000-8000-000000000001') then
    raise exception 'Account deletion left attendance or beta entries behind';
  end if;
end $$;

rollback;
\echo 'Foundation database checks passed.'
