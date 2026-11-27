-- Execute after COPY has placed the payload in the temporary directory_payload table.
with payload as (
  select body from directory_payload
),
batch as (
  insert into jadis_private.directory_import_batches (
    source, source_url, publisher, published_at, sha256,
    row_count, duplicate_count, candidate_count, rejected_count
  )
  select body->>'source', body->>'source_url', body->>'publisher',
    (body->>'published_at')::timestamptz, body->>'sha256',
    (body->>'row_count')::integer, (body->>'duplicates')::integer,
    jsonb_array_length(body->'candidates'), jsonb_array_length(body->'rejected')
  from payload
  on conflict (source, published_at, sha256) do nothing
  returning id
),
candidates as (
  insert into jadis_private.directory_import_candidates
    (batch_id, external_id, uai, name, city, kind, opened_on, closed_on, needs_review)
  select batch.id, entry.external_id, entry.uai, entry.name, entry.city, entry.kind, entry.opened_on, entry.closed_on, entry.needs_review
  from batch cross join payload
  cross join lateral jsonb_to_recordset(body->'candidates')
    as entry(external_id text, uai text, name text, city text, kind text, opened_on date, closed_on date, needs_review boolean)
  returning 1
),
rejections as (
  insert into jadis_private.directory_import_rejections (batch_id, row_number, reason, external_id)
  select batch.id, entry.row_number, entry.reason, entry.external_id
  from batch cross join payload
  cross join lateral jsonb_to_recordset(body->'rejected')
    as entry(row_number integer, reason text, external_id text)
  returning 1
)
select
  (select count(*) from batch) as batches_created,
  (select count(*) from candidates) as candidates_staged,
  (select count(*) from rejections) as rows_quarantined;

commit;
