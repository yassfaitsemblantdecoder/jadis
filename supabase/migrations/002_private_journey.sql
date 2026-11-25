-- Private beta groundwork. Apply after 001.
begin;
create table public.journeys (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 school_id text not null references public.schools(id),
 start_year integer not null check(start_year between 1900 and 2100),
 end_year integer not null check(end_year between 1900 and 2100),
 check(end_year>=start_year),
 unique(user_id,school_id,start_year,end_year)
);
alter table public.journeys enable row level security;
create policy own_journey on public.journeys for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
revoke all on public.journeys from anon;
create index memberships_class_idx on public.memberships(class_id);
create index journeys_school_idx on public.journeys(school_id);
-- No cross-user discovery until consent, blocking and adult-beta gates are tested.
commit;
