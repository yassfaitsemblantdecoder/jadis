begin;

create table jadis_private.timeline_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('school', 'neighborhood', 'work', 'camp', 'association', 'venue', 'other')),
  place text not null check (char_length(place) between 2 and 150 and place !~ '[[:cntrl:]]'),
  city text not null check (char_length(city) between 2 and 120 and city !~ '[[:cntrl:]]'),
  place_key text generated always as (lower(btrim(regexp_replace(place, '[[:space:]]+', ' ', 'g')))) stored,
  city_key text generated always as (lower(btrim(regexp_replace(city, '[[:space:]]+', ' ', 'g')))) stored,
  start_year integer not null check (start_year between 1900 and 2100),
  end_year integer not null check (end_year between start_year and 2100),
  visible boolean not null default false,
  unique (user_id, kind, place_key, city_key, start_year, end_year)
);
create index timeline_visible_place_idx on jadis_private.timeline_entries (kind, place_key, city_key)
  where visible;
alter table jadis_private.timeline_entries enable row level security;
revoke all on jadis_private.timeline_entries from public, anon, authenticated;

create function jadis_private.timeline(action text, entry_id uuid, details jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  saved jadis_private.timeline_entries;
begin
  if actor is null or not jadis_private.eligible(actor)
    or not exists (select 1 from public.profiles p where p.id = actor) then
    raise exception 'Accès réservé';
  end if;

  if action = 'list' then
    return coalesce((
      select jsonb_agg(to_jsonb(t) - array['user_id','place_key','city_key'] order by t.start_year, t.end_year, t.id)
      from jadis_private.timeline_entries t where t.user_id = actor
    ), '[]'::jsonb);
  elsif action = 'delete' then
    delete from jadis_private.timeline_entries t where t.id = entry_id and t.user_id = actor;
    return jsonb_build_object('saved', found);
  elsif action = 'save' then
    if entry_id is null then
      perform pg_advisory_xact_lock(hashtextextended(actor::text, 1));
      if (select count(*) from jadis_private.timeline_entries t where t.user_id = actor) >= 100 then
        raise exception 'Limite de 100 étapes de parcours atteinte';
      end if;
      insert into jadis_private.timeline_entries (user_id, kind, place, city, start_year, end_year, visible)
      values (actor, details->>'kind', btrim(details->>'place'), btrim(details->>'city'),
        (details->>'start_year')::integer, (details->>'end_year')::integer,
        coalesce((details->>'visible')::boolean, false))
      returning * into saved;
    else
      update jadis_private.timeline_entries t
      set kind = details->>'kind', place = btrim(details->>'place'), city = btrim(details->>'city'),
          start_year = (details->>'start_year')::integer, end_year = (details->>'end_year')::integer,
          visible = coalesce((details->>'visible')::boolean, false)
      where t.id = entry_id and t.user_id = actor
      returning * into saved;
      if not found then raise exception 'Étape du parcours indisponible'; end if;
    end if;
    return to_jsonb(saved) - array['user_id','place_key','city_key'];
  end if;
  raise exception 'Action inconnue';
end $$;

create function jadis_private.timeline_crossings(entry_id uuid, memory_year integer)
returns table(person_id uuid, display_name text, first_common_year integer, last_common_year integer)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  anchor jadis_private.timeline_entries;
begin
  if actor is null or not jadis_private.eligible(actor)
     or not exists (select 1 from public.profiles p where p.id = actor and p.discoverable) then
    return;
  end if;
  select t.* into anchor from jadis_private.timeline_entries t
  where t.id = entry_id and t.user_id = actor and t.visible;
  if not found or (memory_year is not null and memory_year not between anchor.start_year and anchor.end_year) then
    return;
  end if;

  insert into jadis_private.discovery_limits(user_id,last_call) values(actor,clock_timestamp())
  on conflict(user_id) do update set last_call=excluded.last_call
  where jadis_private.discovery_limits.last_call < clock_timestamp() - interval '30 seconds';
  if not found then raise exception 'Réessaie dans 30 secondes'; end if;

  return query
    select distinct on (p.id) p.id, p.display_name,
      greatest(anchor.start_year, t.start_year), least(anchor.end_year,t.end_year)
    from jadis_private.timeline_entries t
    join public.profiles p on p.id = t.user_id and p.discoverable
    where t.visible and t.user_id <> actor and t.kind = anchor.kind
      and t.place_key = anchor.place_key and t.city_key = anchor.city_key
      and t.start_year <= anchor.end_year and t.end_year >= anchor.start_year
      and (memory_year is null or memory_year between t.start_year and t.end_year)
      and jadis_private.eligible(t.user_id)
      and not exists (select 1 from public.blocks b
        where (b.owner = actor and b.target = t.user_id) or (b.owner = t.user_id and b.target = actor))
    order by p.id, greatest(anchor.start_year, t.start_year) desc, t.id
    limit 30;
end $$;

create function jadis_private.timeline_overlap(first_member uuid, second_member uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1
    from jadis_private.timeline_entries a
    join jadis_private.timeline_entries b on b.kind = a.kind
      and b.place_key = a.place_key and b.city_key = a.city_key
      and b.start_year <= a.end_year and b.end_year >= a.start_year
    where a.user_id = first_member and b.user_id = second_member and a.visible and b.visible
  )
$$;

create function public.beta_timeline(action text, entry_id uuid default null, details jsonb default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select jadis_private.timeline(action, entry_id, details)
$$;
create function public.beta_timeline_crossings(entry_id uuid, memory_year integer default null)
returns table(person_id uuid, display_name text, first_common_year integer, last_common_year integer)
language sql security invoker set search_path = '' as $$
  select * from jadis_private.timeline_crossings(entry_id, memory_year)
$$;

revoke all on function jadis_private.timeline(text,uuid,jsonb),
  jadis_private.timeline_crossings(uuid,integer), jadis_private.timeline_overlap(uuid,uuid),
  public.beta_timeline(text,uuid,jsonb), public.beta_timeline_crossings(uuid,integer)
from public, anon, authenticated;
grant execute on function jadis_private.timeline(text,uuid,jsonb), jadis_private.timeline_crossings(uuid,integer),
  public.beta_timeline(text,uuid,jsonb), public.beta_timeline_crossings(uuid,integer)
to authenticated;

create or replace function jadis_private.reconnect(action text,target uuid default null,thread uuid default null,content text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); peer uuid; c public.connection_requests%rowtype; result jsonb;
begin
if me is null or not jadis_private.eligible(me) then raise exception 'Accès réservé'; end if;
perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(me::text,0));
if action='list' then
select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from (
select r.id,r.status,r.sender=me as outgoing,p.id as person_id,p.display_name,r.created_at
from public.connection_requests r join public.profiles p on p.id=case when r.sender=me then r.recipient else r.sender end
where (r.sender=me or r.recipient=me) and jadis_private.eligible(p.id)
and not exists(select 1 from public.blocks b where (b.owner=me and b.target=p.id) or (b.owner=p.id and b.target=me))
order by r.created_at desc limit 100) q;
return result;
elsif action='request' then
if target is null or target=me or not jadis_private.eligible(target) or not exists(select 1 from public.profiles p where p.id=me and p.discoverable) or not exists(select 1 from public.profiles p where p.id=target and p.discoverable)
or exists(select 1 from public.blocks b where (b.owner=me and b.target=reconnect.target) or (b.owner=reconnect.target and b.target=me))
or (not exists(select 1 from public.beta_school_entries a join public.beta_school_entries b on a.directory_id=b.directory_id and a.year=b.year where a.user_id=me and b.user_id=target) and not jadis_private.timeline_overlap(me,target))
then raise exception 'Correspondance indisponible'; end if;
if (select count(*) from public.connection_requests where sender=me and created_at>now()-interval '24 hours')>=10 then raise exception 'Limite quotidienne atteinte'; end if;
insert into public.connection_requests(sender,recipient) values(me,target) on conflict do nothing;
return jsonb_build_object('ok',true);
end if;
select * into c from public.connection_requests r where r.id=thread and (r.sender=me or r.recipient=me) for update;
if not found then raise exception 'Conversation indisponible'; end if;
peer:=case when c.sender=me then c.recipient else c.sender end;
if not jadis_private.eligible(peer) or exists(select 1 from public.blocks b where (b.owner=me and b.target=peer) or (b.owner=peer and b.target=me)) then raise exception 'Conversation indisponible'; end if;
if action in ('accept','decline') then
if c.recipient<>me or c.status<>'pending' then raise exception 'Demande indisponible'; end if;
update public.connection_requests set status=case when action='accept' then 'accepted' else 'declined' end where id=c.id;
return jsonb_build_object('ok',true);
end if;
if c.status<>'accepted' then raise exception 'Acceptation mutuelle requise'; end if;
if action='messages' then
select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]'::jsonb) into result from
(select m.id,m.sender=me as outgoing,m.body,m.created_at from jadis_private.messages m where m.connection_id=c.id order by m.created_at desc limit 100) q;
return result;
elsif action='send' then
if content is null or char_length(trim(content)) not between 1 and 2000 then raise exception 'Message invalide'; end if;
if (select count(*) from jadis_private.messages m where m.sender=me and m.created_at>now()-interval '1 minute')>=20 then raise exception 'Limite de messages atteinte'; end if;
insert into jadis_private.messages(connection_id,sender,body) values(c.id,me,trim(content));
return jsonb_build_object('ok',true);
end if;
raise exception 'Action inconnue';
end $$;

commit;
