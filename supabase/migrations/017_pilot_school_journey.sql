begin;

alter table jadis_private.attendance
  add column discoverable boolean not null default false;

create index attendance_pilot_discovery_idx
  on jadis_private.attendance (institution_id, academic_year, user_id)
  where cohort_id is null and discoverable;

create view jadis_private.pilot_school_catalog
with (security_invoker = true) as
select i.id, i.name, i.kind, a.external_id as uai
from jadis_private.directory_pilot_admissions a
join jadis_private.institutions i on i.id = a.institution_id
join jadis_private.institution_identifiers k on k.source = a.identifier_source
  and k.external_id = a.external_id and k.institution_id = i.id
where i.closed_on is null and i.kind in ('primary', 'middle', 'secondary');

revoke all on jadis_private.pilot_school_catalog from public, anon, authenticated;

create function jadis_private.pilot_school(
  requested_action text,
  requested_institution_id uuid,
  requested_academic_year integer,
  requested_discoverable boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  school_name text;
  school_discoverable boolean;
begin
  if actor is null or not jadis_private.eligible(actor)
    or not exists (select 1 from public.profiles p where p.id = actor) then
    raise exception 'Accès réservé';
  end if;

  if requested_action = 'catalog' then
    return coalesce((
      select jsonb_agg(to_jsonb(c) order by c.name, c.id, c.uai)
      from jadis_private.pilot_school_catalog c
    ), '[]'::jsonb);
  elsif requested_action = 'list' then
    -- Keep a member's own steps visible if the school has been taken out of search.
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'institution_id', a.institution_id, 'name', i.name,
        'academic_year', a.academic_year, 'discoverable', a.discoverable
      ) order by a.academic_year, i.name, a.institution_id)
      from jadis_private.attendance a
      join jadis_private.institutions i on i.id = a.institution_id
      where a.user_id = actor and a.cohort_id is null
    ), '[]'::jsonb);
  end if;

  if requested_action is null or requested_action not in ('save', 'delete', 'discover') then
    raise exception 'Action inconnue';
  end if;
  if requested_institution_id is null or requested_academic_year is null
    or requested_academic_year not between 1900 and 2100 then
    raise exception 'Choisis un établissement et une année scolaire de 1900 à 2100';
  end if;

  if requested_action = 'delete' then
    delete from jadis_private.attendance a
    where a.user_id = actor and a.cohort_id is null
      and a.institution_id = requested_institution_id and a.academic_year = requested_academic_year;
    return to_jsonb(found);
  elsif requested_action = 'save' then
    select c.name into school_name
    from jadis_private.pilot_school_catalog c
    where c.id = requested_institution_id;
    if found then
      insert into jadis_private.attendance as a (user_id, institution_id, academic_year, discoverable)
      values (actor, requested_institution_id, requested_academic_year, coalesce(requested_discoverable, false))
      on conflict (user_id, institution_id, academic_year, cohort_id) do update
        set discoverable = excluded.discoverable
      returning a.discoverable into school_discoverable;
    elsif coalesce(requested_discoverable, false) then
      raise exception 'Établissement indisponible';
    else
      -- Allow withdrawal of consent on an existing step after its school leaves the catalogue.
      update jadis_private.attendance a set discoverable = false
      from jadis_private.institutions i
      where a.user_id = actor and a.cohort_id is null and a.institution_id = i.id
        and a.institution_id = requested_institution_id and a.academic_year = requested_academic_year
      returning i.name, a.discoverable into school_name, school_discoverable;
      if not found then raise exception 'Établissement indisponible'; end if;
    end if;

    return jsonb_build_object(
      'institution_id', requested_institution_id, 'name', school_name,
      'academic_year', requested_academic_year, 'discoverable', school_discoverable
    );
  end if;

  if not exists (
    select 1
    from jadis_private.attendance own
    join jadis_private.pilot_school_catalog c on c.id = own.institution_id
    join public.profiles p on p.id = own.user_id and p.discoverable
    where own.user_id = actor and own.cohort_id is null and own.discoverable
      and own.institution_id = requested_institution_id and own.academic_year = requested_academic_year
  ) then
    return '[]'::jsonb;
  end if;

  insert into jadis_private.discovery_limits as limits (user_id, last_call)
  values (actor, clock_timestamp())
  on conflict (user_id) do update set last_call = excluded.last_call
  where limits.last_call < clock_timestamp() - interval '30 seconds';
  if not found then raise exception 'Réessaie dans 30 secondes'; end if;

  return coalesce((
    select jsonb_agg(to_jsonb(matches) order by matches.person_id)
    from (
      select p.id as person_id, p.display_name, c.name as institution_name, other.academic_year
      from jadis_private.attendance own
      join public.profiles actor_profile on actor_profile.id = own.user_id and actor_profile.discoverable
      join jadis_private.pilot_school_catalog c on c.id = own.institution_id
      join jadis_private.attendance other
        on other.institution_id = own.institution_id and other.academic_year = own.academic_year
      join public.profiles p on p.id = other.user_id and p.discoverable
      where own.user_id = actor and own.cohort_id is null and own.discoverable
        and own.institution_id = requested_institution_id and own.academic_year = requested_academic_year
        and jadis_private.eligible(actor)
        and other.user_id <> actor and other.cohort_id is null and other.discoverable
        and jadis_private.eligible(other.user_id)
        and not jadis_private.members_blocked(actor, other.user_id)
      order by p.id limit 30
    ) matches
  ), '[]'::jsonb);
end;
$$;

create function jadis_private.pilot_school_overlap(first_member uuid, second_member uuid)
returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1
    from jadis_private.attendance a
    join jadis_private.attendance b
      on b.institution_id = a.institution_id and b.academic_year = a.academic_year
    join jadis_private.pilot_school_catalog c on c.id = a.institution_id
    where a.user_id = first_member and b.user_id = second_member
      and a.cohort_id is null and b.cohort_id is null and a.discoverable and b.discoverable
  )
$$;

create function public.beta_pilot_school(
  action text, institution_id uuid default null, academic_year integer default null,
  discoverable boolean default false
) returns jsonb
language sql security invoker set search_path = '' as $$
  select jadis_private.pilot_school(action, institution_id, academic_year, discoverable)
$$;

revoke all on function jadis_private.pilot_school(text, uuid, integer, boolean),
  jadis_private.pilot_school_overlap(uuid, uuid), public.beta_pilot_school(text, uuid, integer, boolean)
from public, anon, authenticated;
grant execute on function jadis_private.pilot_school(text, uuid, integer, boolean),
  public.beta_pilot_school(text, uuid, integer, boolean)
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
or (
  not exists(select 1 from public.beta_school_entries a join public.beta_school_entries b on a.directory_id=b.directory_id and a.year=b.year where a.user_id=me and b.user_id=target)
  and not jadis_private.timeline_overlap(me,target)
  and not jadis_private.pilot_school_overlap(me,target)
)
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

create or replace function jadis_private.account_data(action text, confirm boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  now_seconds bigint := extract(epoch from clock_timestamp())::bigint;
begin
  if actor is null or not exists (select 1 from auth.users u where u.id = actor) then
    raise exception 'Accès réservé';
  end if;

  if action = 'export' then
    return jsonb_build_object(
      'exported_at', now(),
      'account', (select jsonb_build_object('email',u.email,'confirmed_at',u.email_confirmed_at)
                  from auth.users u where u.id = actor),
      'profile', (select to_jsonb(p) from public.profiles p where p.id = actor),
      'school_entries', coalesce((select jsonb_agg(to_jsonb(e) - 'user_id' order by e.year,e.id)
                            from public.beta_school_entries e where e.user_id = actor), '[]'::jsonb),
      'school_attendance', coalesce((
        select jsonb_agg(jsonb_build_object(
          'institution_id', a.institution_id, 'name', i.name,
          'academic_year', a.academic_year, 'discoverable', a.discoverable
        ) order by a.academic_year, i.name, a.institution_id)
        from jadis_private.attendance a
        join jadis_private.institutions i on i.id = a.institution_id
        where a.user_id = actor and a.cohort_id is null
      ), '[]'::jsonb),
      'timeline', coalesce((select jsonb_agg(to_jsonb(t) - array['user_id','place_key','city_key'] order by t.start_year,t.id)
                            from jadis_private.timeline_entries t where t.user_id = actor), '[]'::jsonb),
      'saved_searches', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at,n.id)
                            from jadis_private.search_notices n join jadis_private.timeline_entries t on t.id = n.timeline_id
                            where t.user_id = actor), '[]'::jsonb),
      'my_memories', coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'capsule_id',m.capsule_id,
                           'body',m.body,'created_at',m.created_at,'has_photo',p.memory_id is not null)
                           order by m.created_at,m.id)
                           from jadis_private.capsule_memories m
                           left join jadis_private.capsule_photos p on p.memory_id = m.id
                           where m.author_id = actor), '[]'::jsonb)
    );
  elsif action = 'delete' then
    if confirm is distinct from true or not exists (
      select 1 from jsonb_array_elements(coalesce(claims->'amr','[]'::jsonb)) method
      where method->>'method' = 'password'
        and (method->>'timestamp')::bigint between now_seconds - 300 and now_seconds + 5
    ) then raise exception 'Confirme la suppression après une reconnexion par mot de passe'; end if;

    delete from auth.users u where u.id = actor;
    if not found then raise exception 'Compte indisponible'; end if;
    return jsonb_build_object('deleted', true);
  end if;

  raise exception 'Action inconnue';
end $$;

commit;
