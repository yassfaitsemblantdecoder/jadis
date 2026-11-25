begin;
create schema jadis_private;
revoke all on schema jadis_private from public;
grant usage on schema jadis_private to authenticated;
create table jadis_private.discovery_limits(user_id uuid primary key references auth.users(id) on delete cascade,last_call timestamptz not null);
alter table jadis_private.discovery_limits enable row level security;
create index beta_entries_cohort on public.beta_school_entries(directory_id,year,user_id);
grant select,insert,delete on public.blocks to authenticated;
grant insert on public.reports to authenticated;
create policy beta_blocks_gate on public.blocks as restrictive for all to authenticated using(exists(select 1 from public.beta_members where user_id=auth.uid())) with check(exists(select 1 from public.beta_members where user_id=auth.uid()));
create policy beta_reports_gate on public.reports as restrictive for insert to authenticated with check(exists(select 1 from public.beta_members where user_id=auth.uid()));
create function jadis_private.discover() returns table(person_id uuid,display_name text,school_name text,school_year integer,match_type text)
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); n integer;
begin
if me is null or not exists(select 1 from public.beta_members b join auth.users u on u.id=b.user_id where b.user_id=me and u.email_confirmed_at is not null) or not exists(select 1 from public.profiles p where p.id=me and p.discoverable) then return; end if;
insert into jadis_private.discovery_limits(user_id,last_call) values(me,clock_timestamp()) on conflict(user_id) do update set last_call=excluded.last_call where jadis_private.discovery_limits.last_call<clock_timestamp()-interval '30 seconds';
get diagnostics n=row_count;
if n=0 then raise exception 'Réessaie dans 30 secondes'; end if;
return query select distinct on(p.id) p.id,p.display_name,a.school_name,a.year,case when a.level<>'' and a.section<>'' and lower(a.level)=lower(b.level) and lower(a.section)=lower(b.section) then 'classe déclarée' else 'année commune' end
from public.beta_school_entries a join public.beta_school_entries b on a.directory_id=b.directory_id and a.year=b.year and b.user_id<>me
join public.profiles p on p.id=b.user_id and p.discoverable
join public.beta_members m on m.user_id=p.id join auth.users u on u.id=p.id and u.email_confirmed_at is not null
where a.user_id=me and not exists(select 1 from public.blocks k where (k.owner=me and k.target=p.id) or (k.owner=p.id and k.target=me))
order by p.id,a.year desc limit 30;
end $$;
revoke all on function jadis_private.discover() from public,anon;
grant execute on function jadis_private.discover() to authenticated;
create function public.beta_discover() returns table(person_id uuid,display_name text,school_name text,school_year integer,match_type text) language sql security invoker set search_path='' as $$select * from jadis_private.discover()$$;
revoke all on function public.beta_discover() from public,anon;
grant execute on function public.beta_discover() to authenticated;
commit;