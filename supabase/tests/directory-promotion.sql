begin;

insert into jadis_private.institutions (id, name, kind) values
  ('91500000-0000-4000-8000-000000000001', 'École fictive équivalente', 'primary'),
  ('91500000-0000-4000-8000-000000000002', 'École fictive au libellé divergent', 'primary'),
  ('91500000-0000-4000-8000-000000000003', 'École fictive homonyme', 'primary');

insert into jadis_private.institution_identifiers (source, external_id, institution_id) values
  ('uai', '0001102B', '91500000-0000-4000-8000-000000000001'),
  ('uai', '0001103C', '91500000-0000-4000-8000-000000000002'),
  ('uai', '0001109I', '91500000-0000-4000-8000-000000000001'),
  ('closed', ' 0001109i ', '91500000-0000-4000-8000-000000000002'),
  ('uai', '0001110j', '91500000-0000-4000-8000-000000000001'),
  ('paysage', 'fictif-conflit', '91500000-0000-4000-8000-000000000002');

insert into jadis_private.directory_import_batches (
  id, source, source_url, publisher, published_at, sha256,
  row_count, candidate_count, duplicate_count, rejected_count
) values
  ('92500000-0000-4000-8000-000000000001', 'school', 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('1', 64), 16, 16, 0, 0),
  ('92500000-0000-4000-8000-000000000002', 'closed', 'https://data.education.gouv.fr/explore/dataset/fr-en-etablissements-fermes/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('2', 64), 1, 1, 0, 0),
  ('92500000-0000-4000-8000-000000000003', 'higher', 'https://data.enseignementsup-recherche.gouv.fr/explore/dataset/fr-esr-principaux-etablissements-enseignement-superieur/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('3', 64), 2, 2, 0, 0),
  ('92500000-0000-4000-8000-000000000004', 'school', 'https://example.invalid/catalogue/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('4', 64), 1, 1, 0, 0),
  ('92500000-0000-4000-8000-000000000005', 'school', 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('5', 64), 1, 1, 0, 0),
  ('92500000-0000-4000-8000-000000000006', 'school', 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
   'Éditeur fictif', '2026-01-01T00:00:00Z', repeat('6', 64), 1, 0, 0, 1);

insert into jadis_private.directory_import_candidates (
  batch_id, external_id, uai, name, city, kind, closed_on, source_status, needs_review
)
select '92500000-0000-4000-8000-000000000001'::uuid, t.external_id, t.uai, t.name, t.city,
       t.kind, t.closed_on::date, t.source_status, t.needs_review
from (values
  ('0001101A', '0001101A', 'École fictive nouvelle', 'Commune fictive', 'Ecole', null, ' ouvert ', false),
  ('0001102B', '0001102B', 'École fictive équivalente', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001103C', '0001103C', 'École fictive libellée autrement', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001104D', '0001104D', 'École fictive ancienne provenance', 'Commune fictive', 'École', null, null, false),
  ('0001105E', '0001105E', 'École fictive fermée', 'Commune fictive', 'École', null, 'FERMÉ', false),
  ('0001106F', '0001106F', 'Service fictif', 'Commune fictive', 'Service Administratif', null, 'OUVERT', false),
  ('0001107G', '0001107G', 'École fictive sans commune', ' ', 'École', null, 'OUVERT', false),
  ('0001108H', '0001108H', 'ÉCOLE FICTIVE HOMONYME', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001109I', '0001109I', 'École fictive à deux liens', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001110J', '0001110J', 'École fictive avec lien ancien', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001111K', '0001111K', 'École fictive à statut incohérent', 'Commune fictive', 'École', '2010-01-01', 'OUVERT', false),
  ('cle-invalide', '0001112L', 'École fictive sans identifiant cohérent', 'Commune fictive', 'École', null, 'OUVERT', false),
  ('0001113M', '0001113M', 'Collège fictif à revoir', 'Commune fictive', 'Collège', null, 'OUVERT', true),
  ('0001114N', '0001114N', 'Collège fictif du lot', 'Commune fictive', 'Collège', null, 'OUVERT', false),
  ('0001115O', '0001115O', 'COLLÈGE FICTIF   DU LOT', ' COMMUNE FICTIVE ', 'Collège', null, 'OUVERT', false),
  ('0001116P', '0001116P', 'Collège fictif du lot', 'Autre commune fictive', 'Collège', null, 'OUVERT', false)
) as t(external_id, uai, name, city, kind, closed_on, source_status, needs_review);

insert into jadis_private.directory_import_candidates (
  batch_id, external_id, uai, name, city, kind, closed_on, source_status, needs_review
) values
  ('92500000-0000-4000-8000-000000000002', '0001997A', '0001997A', null,
   'Commune fictive', 'École', '2000-02-01', null, true),
  ('92500000-0000-4000-8000-000000000003', 'fictif-paysage', null, 'Université fictive',
   'Commune fictive', 'Université', null, null, false),
  ('92500000-0000-4000-8000-000000000003', 'fictif-conflit', '0001102B', 'Université fictive',
   'Commune fictive', 'Université', null, null, false),
  ('92500000-0000-4000-8000-000000000004', '0001998B', '0001998B', 'École fictive de source inconnue',
   'Commune fictive', 'École', null, 'OUVERT', false);

insert into jadis_private.directory_import_rejections (batch_id, row_number, reason) values
  ('92500000-0000-4000-8000-000000000006', 1, 'missing_identifier');

do $$
declare
  differences jsonb;
begin
  with tested_batches(number, id) as (values
    (1, '92500000-0000-4000-8000-000000000001'::uuid),
    (2, '92500000-0000-4000-8000-000000000002'::uuid),
    (3, '92500000-0000-4000-8000-000000000003'::uuid),
    (4, '92500000-0000-4000-8000-000000000004'::uuid),
    (6, '92500000-0000-4000-8000-000000000006'::uuid)
  ),
  expected(batch_number, external_id, decision, reason, institution_id) as (values
    (1, '0001101A', 'promotable', 'eligible_open_school', null::uuid),
    (1, '0001102B', 'already_equivalent', 'canonical_record_matches', '91500000-0000-4000-8000-000000000001'),
    (1, '0001103C', 'conflict', 'canonical_record_differs', '91500000-0000-4000-8000-000000000002'),
    (1, '0001104D', 'needs_review', 'source_status_missing', null),
    (1, '0001105E', 'needs_review', 'source_status_not_open', null),
    (1, '0001106F', 'needs_review', 'unsupported_school_kind', null),
    (1, '0001107G', 'needs_review', 'municipality_missing', null),
    (1, '0001108H', 'needs_review', 'possible_duplicate_name', null),
    (1, '0001109I', 'conflict', 'identifiers_disagree', null),
    (1, '0001110J', 'needs_review', 'noncanonical_identifier_key', '91500000-0000-4000-8000-000000000001'),
    (1, '0001111K', 'needs_review', 'closure_review_required', null),
    (1, 'cle-invalide', 'needs_review', 'invalid_source_identifier', null),
    (1, '0001113M', 'needs_review', 'staged_review_required', null),
    (1, '0001114N', 'needs_review', 'same_name_and_municipality_in_batch', null),
    (1, '0001115O', 'needs_review', 'same_name_and_municipality_in_batch', null),
    (1, '0001116P', 'promotable', 'eligible_open_school', null),
    (2, '0001997A', 'needs_review', 'staged_review_required', null),
    (3, 'fictif-paysage', 'needs_review', 'source_outside_pilot', null),
    (3, 'fictif-conflit', 'conflict', 'identifiers_disagree', null),
    (4, '0001998B', 'needs_review', 'unverified_catalogue', null)
  ),
  actual as (
    select b.number, p.*
    from tested_batches b
    cross join lateral jadis_private.preview_directory_promotion(b.id) p
  ),
  diff as (
    (select * from actual except all select * from expected)
    union all
    (select * from expected except all select * from actual)
  )
  select jsonb_agg(to_jsonb(d)) into differences from diff d;

  if differences is not null then
    raise exception 'Unexpected directory promotion decisions: %', differences;
  end if;

  if has_function_privilege('anon', 'jadis_private.preview_directory_promotion(uuid)', 'execute')
     or has_function_privilege('authenticated', 'jadis_private.preview_directory_promotion(uuid)', 'execute')
     or to_regprocedure('public.preview_directory_promotion(uuid)') is not null
     or exists (
       select 1 from pg_proc p
       where p.oid = 'jadis_private.preview_directory_promotion(uuid)'::regprocedure
         and (p.prosecdef or p.provolatile <> 's')
     ) then
    raise exception 'Directory preview must be stable, invoker-rights and private';
  end if;

  if exists (select 1 from jadis_private.institutions i where i.name = 'École fictive nouvelle')
     or exists (select 1 from jadis_private.institution_identifiers i where i.external_id = '0001101A') then
    raise exception 'Directory preview wrote to the canonical model';
  end if;

  begin
    perform 1 from jadis_private.preview_directory_promotion('92500000-0000-4000-8000-000000000005');
    raise exception 'Directory preview accepted inconsistent batch counters';
  exception when check_violation then
    null;
  end;

  begin
    perform 1 from jadis_private.preview_directory_promotion('92500000-0000-4000-8000-000000000999');
    raise exception 'Directory preview accepted an unknown batch';
  exception when no_data_found then
    null;
  end;
end;
$$;

set local role authenticated;
do $$
begin
  perform 1 from jadis_private.preview_directory_promotion('92500000-0000-4000-8000-000000000001');
  raise exception 'Authenticated client executed the private directory preview';
exception when insufficient_privilege then
  null;
end;
$$;

rollback;
\echo 'Directory promotion preview checks passed.'
