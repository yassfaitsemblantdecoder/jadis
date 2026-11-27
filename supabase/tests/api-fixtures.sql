create role jadis_api login noinherit;
grant anon, authenticated to jadis_api;

insert into auth.users (id, email_confirmed_at)
select ('00000000-0000-4000-8000-00000000000' || n)::uuid, now()
from generate_series(1, 6) as n;

insert into public.beta_members (user_id)
select id from auth.users where id <> '00000000-0000-4000-8000-000000000003';

insert into public.profiles (id, display_name, discoverable)
select user_id, 'Personne fictive ' || right(user_id::text, 1), true from public.beta_members;

insert into public.beta_school_entries (user_id, directory_id, school_name, year)
select id, 'fixture-shared', 'Établissement fictif', 2008 from public.profiles
where right(id::text, 1) in ('1', '2');
