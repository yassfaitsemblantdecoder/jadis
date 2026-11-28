begin;

insert into jadis_private.institutions (id, name, kind) values
  ('91600000-0000-4000-8000-000000000001', 'Collège fictif existant divergent', 'middle'),
  ('91600000-0000-4000-8000-000000000002', 'Lycée fictif existant identique', 'secondary');

insert into jadis_private.institution_identifiers (source, external_id, institution_id) values
  ('uai', '0001602B', '91600000-0000-4000-8000-000000000001'),
  ('uai', '0001605E', '91600000-0000-4000-8000-000000000002');

insert into jadis_private.directory_import_batches (
  id, source, source_url, publisher, published_at, sha256, row_count, candidate_count,
  duplicate_count, rejected_count
) values
  ('92600000-0000-4000-8000-000000000001', 'school', 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('1', 63) || 'a', 5, 5, 0, 0),
  ('92600000-0000-4000-8000-000000000002', 'school', 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
   'Éditeur fictif', '2026-02-01T00:00:00Z', repeat('2', 63) || 'a', 1, 1, 0, 0),
  ('92600000-0000-4000-8000-000000000003', 'school', 'https://example.invalid/annuaire/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('3', 63) || 'a', 1, 1, 0, 0);

insert into jadis_private.directory_import_candidates (
  batch_id, external_id, uai, name, city, kind, opened_on, source_status, needs_review
) values
  ('92600000-0000-4000-8000-000000000001', '0001601A', '0001601A', 'École fictive à admettre',
   'Commune fictive', 'École', '2000-01-01', 'OUVERT', false),
  ('92600000-0000-4000-8000-000000000001', '0001602B', '0001602B', 'Collège fictif au libellé modifié',
   'Commune fictive', 'Collège', null, 'OUVERT', false),
  ('92600000-0000-4000-8000-000000000001', '0001603C', '0001603C', 'École fictive sans statut',
   'Commune fictive', 'École', null, null, false),
  ('92600000-0000-4000-8000-000000000001', '0001604D', '0001604D', 'Collège fictif hors sélection',
   'Commune fictive', 'Collège', null, 'OUVERT', false),
  ('92600000-0000-4000-8000-000000000001', '0001605E', '0001605E', 'Lycée fictif existant identique',
   'Commune fictive', 'Lycée', null, 'OUVERT', false),
  ('92600000-0000-4000-8000-000000000002', '0001601A', '0001601A', 'École fictive à admettre',
   'Commune fictive', 'École', '2000-01-01', 'OUVERT', false),
  ('92600000-0000-4000-8000-000000000003', '0001606F', '0001606F', 'École fictive de source inconnue',
   'Commune fictive', 'École', null, 'OUVERT', false);

do $$
declare
  batch constant uuid := '92600000-0000-4000-8000-000000000001';
  later_batch constant uuid := '92600000-0000-4000-8000-000000000002';
  choice text[];
  refused text;
  created uuid;
  reported_outcome text;
  replay record;
  original_identity record;
  institutions_before bigint := (select count(*) from jadis_private.institutions);
  identifiers_before bigint := (select count(*) from jadis_private.institution_identifiers);
  admissions_before bigint := (select count(*) from jadis_private.directory_pilot_admissions);
begin
  for choice in
    select t.uais from (values
      (null::text[]),
      (array[]::text[]),
      (array[null]::text[]),
      (array['0001601A','0001601A']),
      (array['0001601a']),
      (array[['0001601A']]),
      (array(select lpad(n::text, 7, '0') || 'A' from generate_series(1, 26) n))
    ) as t(uais)
  loop
    begin
      perform 1 from jadis_private.admit_directory_pilot(batch, choice);
      raise exception 'An invalid pilot selection was accepted';
    exception when invalid_parameter_value then
      null;
    end;
  end loop;

  for refused in select unnest(array['0001602B', '0001603C', '9999999Z']) loop
    begin
      -- The first UAI is eligible, but the second must abort the whole selection.
      perform 1 from jadis_private.admit_directory_pilot(batch, array['0001601A', refused]);
      raise exception 'A mixed selection committed despite a conflict, review or missing UAI';
    exception when check_violation then
      null;
    end;
  end loop;

  begin
    perform 1 from jadis_private.admit_directory_pilot(
      '92600000-0000-4000-8000-000000000003', array['0001606F']);
    raise exception 'A source without verified provenance was admitted';
  exception when check_violation then
    null;
  end;

  if (select count(*) from jadis_private.institutions) <> institutions_before
    or (select count(*) from jadis_private.institution_identifiers) <> identifiers_before
    or (select count(*) from jadis_private.directory_pilot_admissions) <> admissions_before
  then
    raise exception 'Rejected admissions wrote to the canonical model or provenance ledger';
  end if;

  select a.institution_id, a.outcome into strict created, reported_outcome
  from jadis_private.admit_directory_pilot(batch, array['0001601A','0001605E']) a
  where a.external_id = '0001601A';

  if created is null or reported_outcome <> 'admitted'
    or not exists (
      select 1 from jadis_private.institutions i
      join jadis_private.institution_identifiers k on k.institution_id = i.id
      where i.id = created and i.name = 'École fictive à admettre' and i.kind = 'primary'
        and i.closed_on is null and k.source = 'uai' and k.external_id = '0001601A'
    )
  then
    raise exception 'The approved UAI did not create the expected minimal canonical record';
  end if;

  select a.batch_id, a.institution_id, a.admitted_at into strict original_identity
  from jadis_private.directory_pilot_admissions a
  where a.external_id = '0001601A' and a.identifier_source = 'uai';
  if original_identity.batch_id <> batch or original_identity.institution_id <> created
    or original_identity.admitted_at is null
  then
    raise exception 'Pilot admission provenance does not identify the creation lot and target UUID';
  end if;

  select a.* into strict replay from jadis_private.admit_directory_pilot(batch, array['0001605E']) a;
  if replay.outcome <> 'already_equivalent' or replay.institution_id <> '91600000-0000-4000-8000-000000000002'
  then
    raise exception 'An equivalent pre-existing record was not preserved';
  end if;

  select a.* into strict replay from jadis_private.admit_directory_pilot(batch, array['0001601A']) a;
  if replay.outcome <> 'already_equivalent' or replay.institution_id <> created then
    raise exception 'A repeated admission did not return the existing UUID';
  end if;

  select a.* into strict replay from jadis_private.admit_directory_pilot(later_batch, array['0001601A']) a;
  if replay.outcome <> 'already_equivalent' or replay.institution_id <> created then
    raise exception 'An equivalent candidate from a newer batch did not reuse the existing UUID';
  end if;

  if (select count(*) from jadis_private.institutions) <> institutions_before + 1
    or (select count(*) from jadis_private.institution_identifiers) <> identifiers_before + 1
    or (select count(*) from jadis_private.directory_pilot_admissions) <> admissions_before + 1
    or not exists (
      select 1 from jadis_private.directory_pilot_admissions a where a.external_id = '0001601A'
        and a.batch_id = batch and a.institution_id = created and a.admitted_at = original_identity.admitted_at
    )
    or not exists (
      select 1 from jadis_private.institutions i where i.id = '91600000-0000-4000-8000-000000000001'
        and i.name = 'Collège fictif existant divergent' and i.kind = 'middle'
    )
  then
    raise exception 'Replay changed original provenance, wrote an unapproved row or altered an existing institution';
  end if;

  if has_function_privilege('anon', 'jadis_private.admit_directory_pilot(uuid,text[])', 'execute')
    or has_function_privilege('authenticated', 'jadis_private.admit_directory_pilot(uuid,text[])', 'execute')
    or has_table_privilege('anon', 'jadis_private.directory_pilot_admissions', 'select,insert,update,delete')
    or has_table_privilege('authenticated', 'jadis_private.directory_pilot_admissions', 'select,insert,update,delete')
    or to_regprocedure('public.admit_directory_pilot(uuid,text[])') is not null
    or exists (
      select 1 from pg_proc p
      where p.oid = 'jadis_private.admit_directory_pilot(uuid,text[])'::regprocedure and p.prosecdef
    )
  then
    raise exception 'Pilot admission and provenance must be private and use invoker rights';
  end if;
end;
$$;

-- A direct EXECUTE grant must not bypass the owner check.
create role jadis_admission_test_nonowner;
grant usage on schema jadis_private to jadis_admission_test_nonowner;
grant execute on function jadis_private.admit_directory_pilot(uuid, text[]) to jadis_admission_test_nonowner;
set local role jadis_admission_test_nonowner;
do $$
declare
  rejection text;
begin
  perform 1 from jadis_private.admit_directory_pilot(
    '92600000-0000-4000-8000-000000000001', array['0001601A']);
  raise exception 'A nonowner executed the pilot admission function';
exception when insufficient_privilege then
  get stacked diagnostics rejection = message_text;
  if rejection <> 'Directory admission is restricted to the function owner' then
    raise;
  end if;
end;
$$;
rollback;

begin isolation level repeatable read;
do $$
begin
  perform 1 from jadis_private.admit_directory_pilot(
    '92600000-0000-4000-8000-000000000001', array['0001601A']);
  raise exception 'The pilot admission accepted an isolation level that blocks refreshing the preview';
exception when invalid_transaction_state then
  null;
end;
$$;
rollback;

\echo 'Directory pilot admission checks passed.'
