-- Qualify the request argument in the query over public.blocks.
-- Preserve the public RPC signature and existing grants.
begin;

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
or not exists(select 1 from public.beta_school_entries a join public.beta_school_entries b on a.directory_id=b.directory_id and a.year=b.year where a.user_id=me and b.user_id=target)
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
