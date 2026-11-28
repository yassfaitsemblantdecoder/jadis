-- Shared synthetic directory fixture, including one canonical institution outside the pilot.
insert into jadis_private.directory_import_batches (
  id, source, source_url, publisher, published_at, sha256,
  row_count, duplicate_count, candidate_count, rejected_count
) values (
  '10000000-0000-4000-8000-000000000170', 'school',
  'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/',
  'Source fictive', '2026-01-01T00:00:00Z', repeat('a', 64),
  3, 0, 3, 0
);

insert into jadis_private.directory_import_candidates (
  batch_id, external_id, uai, name, city, kind, source_status, needs_review
) values
  ('10000000-0000-4000-8000-000000000170', '0000170A', '0000170A',
   'École pilote fictive', 'Commune fictive', 'Ecole', 'OUVERT', false),
  ('10000000-0000-4000-8000-000000000170', '0000171B', '0000171B',
   'Collège pilote fictif', 'Commune fictive', 'Collège', 'OUVERT', false),
  ('10000000-0000-4000-8000-000000000170', '0000172C', '0000172C',
   'École retirée fictive', 'Commune fictive', 'Ecole', 'OUVERT', false);

select outcome from jadis_private.admit_directory_pilot(
  '10000000-0000-4000-8000-000000000170', array['0000170A','0000171B','0000172C']
);

insert into jadis_private.institutions(id, name, kind)
values ('10000000-0000-4000-8000-000000000179', 'École hors pilote fictive', 'primary');

-- An earlier attendance must stay withdrawable even after its school closes.
update jadis_private.institutions i set closed_on = date '2026-01-02'
from jadis_private.institution_identifiers k
where k.source = 'uai' and k.external_id = '0000172C' and k.institution_id = i.id;

insert into jadis_private.attendance (user_id, institution_id, academic_year, discoverable)
select p.id, k.institution_id, 2007, true
from public.profiles p
cross join jadis_private.institution_identifiers k
where p.id = '00000000-0000-4000-8000-000000000009'
  and k.source = 'uai' and k.external_id = '0000172C';
