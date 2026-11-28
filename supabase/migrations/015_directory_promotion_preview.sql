begin;

alter table jadis_private.directory_import_candidates
  add column source_status text
    check (source_status is null or (
      char_length(source_status) between 1 and 80 and btrim(source_status) <> ''
    ));

create function jadis_private.preview_directory_promotion(batch_uuid uuid)
returns table (
  external_id text,
  decision text,
  reason text,
  institution_id uuid
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  selected_batch jadis_private.directory_import_batches%rowtype;
  expected_url text;
begin
  select b.* into strict selected_batch
  from jadis_private.directory_import_batches b
  where b.id = batch_uuid;

  if selected_batch.candidate_count <> (
    select count(*) from jadis_private.directory_import_candidates c where c.batch_id = batch_uuid
  ) or selected_batch.rejected_count <> (
    select count(*) from jadis_private.directory_import_rejections r where r.batch_id = batch_uuid
  ) then
    raise exception 'Directory import batch counters do not match staged rows'
      using errcode = 'check_violation';
  end if;

  expected_url := case selected_batch.source
    when 'school' then 'https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/'
    when 'closed' then 'https://data.education.gouv.fr/explore/dataset/fr-en-etablissements-fermes/'
    when 'higher' then 'https://data.enseignementsup-recherche.gouv.fr/explore/dataset/fr-esr-principaux-etablissements-enseignement-superieur/'
  end;

  return query
    with candidates as (
      select c.*,
             lower(btrim(regexp_replace(c.name, '[[:space:]]+', ' ', 'g'))) as name_key,
             lower(btrim(regexp_replace(c.city, '[[:space:]]+', ' ', 'g'))) as city_key,
             case lower(btrim(c.kind))
        when 'ecole' then 'primary'
        when 'école' then 'primary'
        when 'collège' then 'middle'
        when 'lycée' then 'secondary'
      end as canonical_kind
      from jadis_private.directory_import_candidates c
      where c.batch_id = batch_uuid
    ),
    repeated_names as (
      select c.name_key, c.city_key
      from candidates c
      where selected_batch.source = 'school' and c.name_key <> '' and c.city_key <> ''
      group by c.name_key, c.city_key
      having count(*) > 1
    ),
    matches as (
      -- Legacy namespace or spelling can signal a collision, but cannot establish a canonical key.
      select c.external_id as candidate_key, k.institution_id,
             k.source = 'uai' and k.external_id = c.uai as exact_uai
      from candidates c
      join jadis_private.institution_identifiers k on upper(btrim(k.external_id)) = c.uai
      where k.source in ('uai', 'school', 'closed')
      union all
      select c.external_id, k.institution_id, false
      from candidates c
      join jadis_private.institution_identifiers k on (
        (k.source = 'paysage' and btrim(k.external_id) = c.external_id)
        or (k.source = 'higher' and btrim(k.external_id) in (c.external_id, 'esr:' || c.external_id))
      )
      where selected_batch.source = 'higher'
    ),
    links as (
      select m.candidate_key, array_agg(distinct m.institution_id) as target_ids,
             bool_or(m.exact_uai) as exact_uai
      from matches m
      group by m.candidate_key
    ),
    existing_names as (
      select distinct lower(btrim(regexp_replace(i.name, '[[:space:]]+', ' ', 'g'))) as name_key
      from jadis_private.institutions i
    ),
    assessed as (
      select c.external_id, i.id, case
        when selected_batch.source_url is distinct from expected_url then 'unverified_catalogue'
        when c.external_id <> btrim(c.external_id)
          or (selected_batch.source in ('school', 'closed') and c.external_id is distinct from c.uai)
          then 'invalid_source_identifier'
        when cardinality(l.target_ids) > 1 then 'identifiers_disagree'
        when c.needs_review or nullif(btrim(c.name), '') is null then 'staged_review_required'
        when selected_batch.source <> 'school' then 'source_outside_pilot'
        when c.source_status is null then 'source_status_missing'
        when upper(btrim(c.source_status)) <> 'OUVERT' then 'source_status_not_open'
        when c.closed_on is not null then 'closure_review_required'
        when c.canonical_kind is null then 'unsupported_school_kind'
        when nullif(c.city_key, '') is null then 'municipality_missing'
        when r.name_key is not null then 'same_name_and_municipality_in_batch'
        when i.id is not null and not l.exact_uai then 'noncanonical_identifier_key'
        -- The canonical record does not include a municipality.
        when i.id is not null and (
          btrim(i.name) <> btrim(c.name) or i.kind <> c.canonical_kind or i.closed_on is not null
        ) then 'canonical_record_differs'
        when i.id is not null then 'canonical_record_matches'
        when n.name_key is not null then 'possible_duplicate_name'
        else 'eligible_open_school'
      end as finding
      from candidates c
      left join links l on l.candidate_key = c.external_id
      left join jadis_private.institutions i on cardinality(l.target_ids) = 1 and i.id = l.target_ids[1]
      left join repeated_names r on r.name_key = c.name_key and r.city_key = c.city_key
      left join existing_names n on n.name_key = c.name_key
    )
    select a.external_id,
           case a.finding
             when 'eligible_open_school' then 'promotable'
             when 'canonical_record_matches' then 'already_equivalent'
             when 'identifiers_disagree' then 'conflict'
             when 'canonical_record_differs' then 'conflict'
             else 'needs_review'
           end,
           a.finding,
           case when a.finding not in ('unverified_catalogue', 'invalid_source_identifier') then a.id end
    from assessed a
    order by a.external_id;
end;
$$;

revoke all on function jadis_private.preview_directory_promotion(uuid) from public, anon, authenticated;

commit;
