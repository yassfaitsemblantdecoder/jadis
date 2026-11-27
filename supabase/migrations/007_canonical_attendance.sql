begin;

create table jadis_private.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 300),
  kind text not null check (kind in ('primary', 'middle', 'secondary', 'higher', 'other')),
  closed_on date
);

create table jadis_private.institution_identifiers (
  source text not null check (char_length(btrim(source)) between 1 and 80),
  external_id text not null check (char_length(btrim(external_id)) between 1 and 150),
  institution_id uuid not null references jadis_private.institutions(id),
  recorded_at timestamptz not null default now(),
  primary key (source, external_id)
);

create table jadis_private.institution_names (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references jadis_private.institutions(id),
  name text not null check (char_length(btrim(name)) between 1 and 300),
  valid_from date,
  valid_until date,
  check (valid_until is null or valid_from is null or valid_from < valid_until)
);

create table jadis_private.cohorts (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references jadis_private.institutions(id),
  academic_year integer not null check (academic_year between 1900 and 2100),
  level text not null check (char_length(btrim(level)) between 1 and 80),
  section text not null default '' check (char_length(section) <= 30),
  unique (institution_id, academic_year, level, section),
  unique (id, institution_id, academic_year)
);

create table jadis_private.attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  institution_id uuid not null references jadis_private.institutions(id),
  academic_year integer not null check (academic_year between 1900 and 2100),
  cohort_id uuid,
  declared_at timestamptz not null default now(),
  foreign key (cohort_id, institution_id, academic_year)
    references jadis_private.cohorts (id, institution_id, academic_year),
  unique nulls not distinct (user_id, institution_id, academic_year, cohort_id)
);

create index institution_identifiers_institution_idx
  on jadis_private.institution_identifiers (institution_id);
create index institution_names_institution_idx
  on jadis_private.institution_names (institution_id);
create index attendance_institution_year_idx
  on jadis_private.attendance (institution_id, academic_year);
create index attendance_cohort_idx on jadis_private.attendance (cohort_id)
  where cohort_id is not null;

alter table jadis_private.institutions enable row level security;
alter table jadis_private.institution_identifiers enable row level security;
alter table jadis_private.institution_names enable row level security;
alter table jadis_private.cohorts enable row level security;
alter table jadis_private.attendance enable row level security;

revoke all on table
  jadis_private.institutions,
  jadis_private.institution_identifiers,
  jadis_private.institution_names,
  jadis_private.cohorts,
  jadis_private.attendance
from public, anon, authenticated;

commit;
