begin;

create table jadis_private.capsules (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 100 and title !~ '[[:cntrl:]]'),
  kind text not null,
  place_key text not null,
  city_key text not null,
  memory_year integer not null check (memory_year between 1900 and 2100),
  created_at timestamptz not null default now()
);
create index capsules_owner_idx on jadis_private.capsules (owner_id);

create table jadis_private.capsule_members (
  capsule_id uuid not null references jadis_private.capsules(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  accepted_at timestamptz,
  primary key (capsule_id, member_id)
);
create index capsule_members_member_idx on jadis_private.capsule_members (member_id);

create table jadis_private.capsule_memories (
  id uuid primary key default gen_random_uuid(),
  capsule_id uuid not null,
  author_id uuid not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  foreign key (capsule_id, author_id) references jadis_private.capsule_members (capsule_id, member_id) on delete cascade
);
create index capsule_memories_recent_idx on jadis_private.capsule_memories (capsule_id, created_at desc, id desc);
create index capsule_memories_author_idx on jadis_private.capsule_memories (capsule_id, author_id);

alter table jadis_private.capsules enable row level security;
alter table jadis_private.capsule_members enable row level security;
alter table jadis_private.capsule_memories enable row level security;
revoke all on jadis_private.capsules, jadis_private.capsule_members, jadis_private.capsule_memories
from public, anon, authenticated;

create function jadis_private.members_blocked(first_member uuid, second_member uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.blocks b where
    (b.owner = first_member and b.target = second_member)
    or (b.owner = second_member and b.target = first_member))
$$;
revoke all on function jadis_private.members_blocked(uuid,uuid) from public, anon, authenticated;

create function jadis_private.memory_capsules(action text, capsule_id uuid, details jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  selected jadis_private.capsules;
  anchor jadis_private.timeline_entries;
  target_member uuid;
  memory_year integer;
  accepted timestamptz;
  memory_id uuid;
begin
  if actor is null or not jadis_private.eligible(actor)
    or not exists (select 1 from public.profiles p where p.id = actor) then
    raise exception 'Accès réservé';
  end if;

  if action = 'list' then
    return coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc, q.id)
      from (
        select c.id, c.title, c.memory_year, c.created_at, c.owner_id = actor as owned,
               m.accepted_at is not null as joined
        from jadis_private.capsule_members m
        join jadis_private.capsules c on c.id = m.capsule_id
        where m.member_id = actor and jadis_private.eligible(c.owner_id)
          and not jadis_private.members_blocked(actor, c.owner_id)
      ) q
    ), '[]'::jsonb);
  elsif action = 'create' then
    memory_year := (details->>'year')::integer;
    select t.* into anchor from jadis_private.timeline_entries t
    where t.id = (details->>'entry_id')::uuid and t.user_id = actor and t.visible
      and memory_year between t.start_year and t.end_year;
    if not found then raise exception 'Lieu ou période indisponible'; end if;
    perform pg_advisory_xact_lock(hashtextextended(actor::text, 2));
    if (select count(*) from jadis_private.capsules c where c.owner_id = actor) >= 20 then
      raise exception 'Limite de capsules atteinte';
    end if;
    insert into jadis_private.capsules (owner_id, title, kind, place_key, city_key, memory_year)
    values (actor, btrim(details->>'title'), anchor.kind, anchor.place_key, anchor.city_key, memory_year)
    returning * into selected;
    insert into jadis_private.capsule_members (capsule_id, member_id, accepted_at)
    values (selected.id, actor, now());
    return jsonb_build_object('id', selected.id);
  end if;

  select c.* into selected from jadis_private.capsules c
  where c.id = memory_capsules.capsule_id for update;
  if not found then raise exception 'Capsule indisponible'; end if;
  select m.accepted_at into accepted from jadis_private.capsule_members m
  where m.capsule_id = selected.id and m.member_id = actor;
  if not found then raise exception 'Capsule indisponible'; end if;

  if action = 'leave' then
    if selected.owner_id = actor then
      delete from jadis_private.capsules c where c.id = selected.id;
    else
      delete from jadis_private.capsule_members m where m.capsule_id = selected.id and m.member_id = actor;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  if not jadis_private.eligible(selected.owner_id) or jadis_private.members_blocked(actor, selected.owner_id) then
    raise exception 'Capsule indisponible';
  end if;

  if action = 'join' then
    update jadis_private.capsule_members m set accepted_at = now()
    where m.capsule_id = selected.id and m.member_id = actor and m.accepted_at is null;
    return jsonb_build_object('ok', true);
  end if;
  if accepted is null then raise exception 'Invitation à accepter'; end if;

  if action = 'invite' then
    if selected.owner_id <> actor then raise exception 'Seul le créateur peut inviter'; end if;
    target_member := (details->>'member_id')::uuid;
    if target_member is null or target_member = actor or not jadis_private.eligible(target_member)
      or jadis_private.members_blocked(actor, target_member)
      or not exists (select 1 from public.connection_requests r where r.status = 'accepted' and (
        (r.sender = actor and r.recipient = target_member) or (r.sender = target_member and r.recipient = actor)))
      or not exists (select 1 from jadis_private.timeline_entries t where t.user_id = target_member and t.visible
        and t.kind = selected.kind and t.place_key = selected.place_key and t.city_key = selected.city_key
        and selected.memory_year between t.start_year and t.end_year)
    then raise exception 'Invitation indisponible pour ce contact et cette période'; end if;
    if exists (select 1 from jadis_private.capsule_members m
      where m.capsule_id = selected.id and m.member_id = target_member) then
      return jsonb_build_object('ok', true);
    end if;
    if (select count(*) from jadis_private.capsule_members m where m.capsule_id = selected.id) >= 20 then
      raise exception 'Limite de membres atteinte';
    end if;
    insert into jadis_private.capsule_members (capsule_id, member_id)
    values (selected.id, target_member) on conflict do nothing;
    return jsonb_build_object('ok', true);
  elsif action = 'read' then
    return coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at, q.id) from (
        select m.id, m.author_id, p.display_name, m.author_id = actor as mine, m.body, m.created_at
        from jadis_private.capsule_memories m
        join public.profiles p on p.id = m.author_id
        where m.capsule_id = selected.id and jadis_private.eligible(m.author_id)
          and not jadis_private.members_blocked(actor, m.author_id)
        order by m.created_at desc, m.id desc limit 100
      ) q
    ), '[]'::jsonb);
  elsif action = 'post' then
    if (select count(*) from jadis_private.capsule_memories m where m.capsule_id = selected.id) >= 100 then
      raise exception 'Limite de souvenirs atteinte';
    end if;
    insert into jadis_private.capsule_memories (capsule_id, author_id, body)
    values (selected.id, actor, btrim(details->>'body')) returning id into memory_id;
    return jsonb_build_object('id', memory_id);
  elsif action = 'remove' then
    delete from jadis_private.capsule_memories m
    where m.id = (details->>'memory_id')::uuid and m.capsule_id = selected.id and m.author_id = actor;
    return jsonb_build_object('ok', found);
  end if;
  raise exception 'Action inconnue';
end $$;

create function public.beta_capsules(action text, capsule_id uuid default null, details jsonb default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select jadis_private.memory_capsules(action, capsule_id, details)
$$;
revoke all on function jadis_private.memory_capsules(text,uuid,jsonb), public.beta_capsules(text,uuid,jsonb)
from public, anon, authenticated;
grant execute on function jadis_private.memory_capsules(text,uuid,jsonb), public.beta_capsules(text,uuid,jsonb)
to authenticated;

commit;
