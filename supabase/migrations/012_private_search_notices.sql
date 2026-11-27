begin;

create table jadis_private.search_notices (
  id uuid primary key default gen_random_uuid(),
  timeline_id uuid not null references jadis_private.timeline_entries(id) on delete cascade,
  memory_year integer check (memory_year between 1900 and 2100),
  created_at timestamptz not null default now(),
  unique nulls not distinct (timeline_id, memory_year)
);
alter table jadis_private.search_notices enable row level security;
revoke all on jadis_private.search_notices from public, anon, authenticated;

create function jadis_private.search_notices(action text, notice_id uuid, entry_id uuid, memory_year integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not jadis_private.eligible(actor) then raise exception 'Accès réservé'; end if;
  if action = 'list' then
    return coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc, q.id)
      from (
        select n.id, n.timeline_id as entry_id, n.memory_year, n.created_at, t.place, t.city,
          (t.visible and (n.memory_year is null or n.memory_year between t.start_year and t.end_year)) as available
        from jadis_private.search_notices n join jadis_private.timeline_entries t on t.id = n.timeline_id
        where t.user_id = actor
      ) q
    ), '[]'::jsonb);
  elsif action = 'save' then
    perform pg_advisory_xact_lock(hashtextextended(actor::text, 3));
    if not exists (select 1 from jadis_private.timeline_entries t where t.id = entry_id and t.user_id = actor
        and (search_notices.memory_year is null or search_notices.memory_year between t.start_year and t.end_year))
    then raise exception 'Lieu ou période indisponible'; end if;
    if exists (select 1 from jadis_private.search_notices n where n.timeline_id = entry_id
        and n.memory_year is not distinct from search_notices.memory_year) then
      return jsonb_build_object('saved', true);
    end if;
    if (select count(*) from jadis_private.search_notices n join jadis_private.timeline_entries t on t.id = n.timeline_id
        where t.user_id = actor) >= 40 then
      raise exception 'Limite de recherches enregistrées atteinte';
    end if;
    insert into jadis_private.search_notices (timeline_id, memory_year)
    values (entry_id, search_notices.memory_year) on conflict do nothing;
    return jsonb_build_object('saved', true);
  elsif action = 'delete' then
    delete from jadis_private.search_notices n using jadis_private.timeline_entries t
    where n.id = notice_id and n.timeline_id = t.id and t.user_id = actor;
    return jsonb_build_object('saved', found);
  end if;
  raise exception 'Action inconnue';
end $$;

create function public.beta_search_notices(action text, notice_id uuid default null,
  entry_id uuid default null, memory_year integer default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select jadis_private.search_notices(action, notice_id, entry_id, memory_year)
$$;
revoke all on function jadis_private.search_notices(text,uuid,uuid,integer),
  public.beta_search_notices(text,uuid,uuid,integer) from public, anon, authenticated;
grant execute on function jadis_private.search_notices(text,uuid,uuid,integer),
  public.beta_search_notices(text,uuid,uuid,integer) to authenticated;

commit;
