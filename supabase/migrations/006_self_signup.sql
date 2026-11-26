begin;
create table jadis_private.invite_codes(code_hash text primary key,expires_at timestamptz not null,used_by uuid references auth.users(id) on delete set null,used_at timestamptz);
alter table jadis_private.invite_codes enable row level security;
revoke all on jadis_private.invite_codes from public,anon,authenticated;
create table jadis_private.invite_attempts(user_id uuid primary key references auth.users(id) on delete cascade,window_start timestamptz not null,attempts integer not null);
alter table jadis_private.invite_attempts enable row level security;
revoke all on jadis_private.invite_attempts from public,anon,authenticated;
create function jadis_private.redeem_invite(code text,adult boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); n integer; tries integer;
begin
if me is null or adult is distinct from true or not exists(select 1 from auth.users u where u.id=me and u.email_confirmed_at is not null) then return false; end if;
if exists(select 1 from public.beta_members b where b.user_id=me) then return true; end if;
if code is null or char_length(code)>100 then return false; end if;
insert into jadis_private.invite_attempts(user_id,window_start,attempts) values(me,now(),1) on conflict(user_id) do update set attempts=case when jadis_private.invite_attempts.window_start<now()-interval '1 hour' then 1 else jadis_private.invite_attempts.attempts+1 end,window_start=case when jadis_private.invite_attempts.window_start<now()-interval '1 hour' then now() else jadis_private.invite_attempts.window_start end returning attempts into tries;
if tries>10 then return false; end if;
update jadis_private.invite_codes set used_by=me,used_at=now() where code_hash=encode(sha256(convert_to(upper(trim(code)),'UTF8')),'hex') and used_at is null and expires_at>now();
get diagnostics n=row_count;
if n<>1 then return false; end if;
insert into public.beta_members(user_id) values(me) on conflict do nothing;
return true;
end $$;
revoke all on function jadis_private.redeem_invite(text,boolean) from public,anon;
grant execute on function jadis_private.redeem_invite(text,boolean) to authenticated;
create function public.beta_redeem_invite(code text,adult boolean) returns boolean language sql security invoker set search_path='' as $$select jadis_private.redeem_invite(code,adult)$$;
revoke all on function public.beta_redeem_invite(text,boolean) from public,anon;
grant execute on function public.beta_redeem_invite(text,boolean) to authenticated;
commit;