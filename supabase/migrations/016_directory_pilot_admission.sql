begin;

create table jadis_private.directory_pilot_admissions (
  external_id text primary key,
  identifier_source text not null default 'uai' check (identifier_source = 'uai'),
  institution_id uuid not null references jadis_private.institutions(id),
  batch_id uuid not null,
  admitted_at timestamptz not null default now(),
  foreign key (identifier_source, external_id)
    references jadis_private.institution_identifiers(source, external_id),
  foreign key (batch_id, external_id)
    references jadis_private.directory_import_candidates(batch_id, external_id)
);
create index directory_pilot_admissions_batch_idx
  on jadis_private.directory_pilot_admissions(batch_id);
create index directory_pilot_admissions_institution_idx
  on jadis_private.directory_pilot_admissions(institution_id);

alter table jadis_private.directory_pilot_admissions enable row level security;
revoke all on jadis_private.directory_pilot_admissions from public, anon, authenticated;

create function jadis_private.admit_directory_pilot(batch_uuid uuid, approved_uais text[])
returns table (
  external_id text,
  institution_id uuid,
  outcome text
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  candidate record;
begin
  if current_user <> (
    select pg_get_userbyid(p.proowner)
    from pg_proc p
    where p.oid = 'jadis_private.admit_directory_pilot(uuid,text[])'::regprocedure
  ) then
    raise exception 'Directory admission is restricted to the function owner'
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(array_ndims(approved_uais), 0) <> 1
    or cardinality(approved_uais) not between 1 and 25
    or exists (
      select 1 from unnest(approved_uais) as u(uai)
      where u.uai is null or u.uai !~ '^[0-9]{7}[A-Z]$'
    )
    or cardinality(approved_uais) <> (select count(distinct u.uai) from unnest(approved_uais) as u(uai))
  then
    raise exception 'Select between 1 and 25 distinct canonical UAI values'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Re-read the preview in a new snapshot after any concurrent admission commits.
  if current_setting('transaction_isolation') not in ('read committed', 'read uncommitted') then
    raise exception 'Directory admission requires read committed isolation'
      using errcode = 'invalid_transaction_state';
  end if;

  lock table jadis_private.directory_import_batches,
    jadis_private.directory_import_candidates,
    jadis_private.directory_import_rejections in share mode;
  lock table jadis_private.institutions,
    jadis_private.institution_identifiers,
    jadis_private.directory_pilot_admissions in share row exclusive mode;

  for candidate in
    select u.uai, p.decision, p.reason, p.institution_id, btrim(c.name) as name,
      case lower(btrim(c.kind))
        when 'ecole' then 'primary'
        when 'école' then 'primary'
        when 'collège' then 'middle'
        when 'lycée' then 'secondary'
      end as canonical_kind
    from unnest(approved_uais) with ordinality as u(uai, position)
    left join jadis_private.preview_directory_promotion(batch_uuid) p on p.external_id = u.uai
    left join jadis_private.directory_import_candidates c
      on c.batch_id = batch_uuid and c.external_id = u.uai
    order by u.position
  loop
    external_id := candidate.uai;
    if candidate.decision = 'already_equivalent' then
      if exists (
        select 1 from jadis_private.directory_pilot_admissions a
        where a.external_id = candidate.uai and a.institution_id <> candidate.institution_id
      ) then
        raise exception 'Recorded admission target changed for UAI %', candidate.uai
          using errcode = 'check_violation';
      end if;
      institution_id := candidate.institution_id;
      outcome := 'already_equivalent';
    elsif candidate.decision = 'promotable' then
      insert into jadis_private.institutions as i (name, kind)
      values (candidate.name, candidate.canonical_kind)
      returning i.id into institution_id;

      insert into jadis_private.institution_identifiers (source, external_id, institution_id)
      values ('uai', candidate.uai, institution_id);

      insert into jadis_private.directory_pilot_admissions (batch_id, external_id, institution_id)
      values (batch_uuid, candidate.uai, institution_id);
      outcome := 'admitted';
    else
      raise exception 'UAI % cannot be admitted from this lot: %',
        candidate.uai, coalesce(candidate.reason, 'not_in_batch')
        using errcode = 'check_violation';
    end if;
    return next;
  end loop;
end;
$$;

revoke all on function jadis_private.admit_directory_pilot(uuid, text[]) from public, anon, authenticated;

commit;
