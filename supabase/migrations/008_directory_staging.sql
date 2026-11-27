begin;

create table jadis_private.directory_import_batches (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('school', 'closed', 'higher')),
  source_url text not null,
  publisher text not null check (btrim(publisher) <> ''),
  published_at timestamptz not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  row_count integer not null check (row_count > 0),
  duplicate_count integer not null check (duplicate_count >= 0),
  candidate_count integer not null check (candidate_count >= 0),
  rejected_count integer not null check (rejected_count >= 0),
  imported_at timestamptz not null default now(),
  unique (source, published_at, sha256),
  check (row_count = duplicate_count + candidate_count + rejected_count)
);

create table jadis_private.directory_import_candidates (
  batch_id uuid not null references jadis_private.directory_import_batches(id) on delete cascade,
  external_id text not null check (char_length(external_id) between 1 and 150),
  uai text check (uai ~ '^[0-9]{7}[A-Z]$'),
  name text check (char_length(btrim(name)) between 1 and 300),
  city text check (char_length(city) <= 150),
  kind text check (char_length(kind) <= 150),
  opened_on date,
  closed_on date,
  needs_review boolean not null,
  check (name is not null or (needs_review and closed_on is not null)),
  primary key (batch_id, external_id),
  check (opened_on is null or closed_on is null or opened_on <= closed_on)
);

create table jadis_private.directory_import_rejections (
  batch_id uuid not null references jadis_private.directory_import_batches(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  reason text not null check (reason in (
    'invalid_field_type', 'invalid_field_value', 'invalid_date', 'missing_identifier',
    'missing_name', 'invalid_closure_period', 'identifier_conflict'
  )),
  external_id text,
  primary key (batch_id, row_number)
);

alter table jadis_private.directory_import_batches enable row level security;
alter table jadis_private.directory_import_candidates enable row level security;
alter table jadis_private.directory_import_rejections enable row level security;

revoke all on table
  jadis_private.directory_import_batches,
  jadis_private.directory_import_candidates,
  jadis_private.directory_import_rejections
from public, anon, authenticated;

commit;
