begin;

create function jadis_private.account_data(action text, confirm boolean) returns jsonb
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

create function public.beta_account_data(action text, confirm boolean default false)
returns jsonb language sql security invoker set search_path = '' as $$
  select jadis_private.account_data(action, confirm)
$$;
revoke all on function jadis_private.account_data(text,boolean), public.beta_account_data(text,boolean)
from public, anon, authenticated;
grant execute on function jadis_private.account_data(text,boolean), public.beta_account_data(text,boolean)
to authenticated;

commit;
