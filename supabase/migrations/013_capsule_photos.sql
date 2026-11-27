begin;

-- Store bounded RGB pixels rather than an original file or its metadata.
create table jadis_private.capsule_photos (
  memory_id uuid primary key references jadis_private.capsule_memories(id) on delete cascade,
  width integer not null check (width between 1 and 192),
  height integer not null check (height between 1 and 192),
  pixels bytea not null,
  check (octet_length(pixels) = width * height * 3)
);
alter table jadis_private.capsule_photos enable row level security;
revoke all on jadis_private.capsule_photos from public, anon, authenticated;

create function jadis_private.capsule_photos(action text, capsule_id uuid, details jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  visible_memories jsonb;
  memory_id uuid;
  pixel_width integer;
  pixel_height integer;
  encoded text;
  raw_pixels bytea;
begin
  if action = 'post' then
    pixel_width := (details->>'width')::integer;
    pixel_height := (details->>'height')::integer;
    encoded := details->>'pixels';
    if pixel_width is null or pixel_height is null or encoded is null
      or pixel_width not between 1 and 192 or pixel_height not between 1 and 192
      or char_length(encoded) <> 4 * ((pixel_width * pixel_height * 3 + 2) / 3)
    then raise exception 'Photo invalide'; end if;
    raw_pixels := decode(encoded, 'base64');
    if octet_length(raw_pixels) <> pixel_width * pixel_height * 3 then
      raise exception 'Photo invalide';
    end if;
    memory_id := (jadis_private.memory_capsules('post', capsule_id, details)->>'id')::uuid;
    insert into jadis_private.capsule_photos (memory_id, width, height, pixels)
    values (memory_id, pixel_width, pixel_height, raw_pixels);
    return jsonb_build_object('id', memory_id);
  end if;

  visible_memories := jadis_private.memory_capsules('read', capsule_id, null);
  if action = 'list' then
    return coalesce((
      select jsonb_agg(p.memory_id)
      from jsonb_array_elements(visible_memories) m
      join jadis_private.capsule_photos p on p.memory_id = (m->>'id')::uuid
    ), '[]'::jsonb);
  elsif action = 'read' then
    return (
      select jsonb_build_object('width', p.width, 'height', p.height,
        'pixels', replace(encode(p.pixels, 'base64'), E'\n', ''))
      from jsonb_array_elements(visible_memories) m
      join jadis_private.capsule_photos p on p.memory_id = (m->>'id')::uuid
      where p.memory_id = (details->>'memory_id')::uuid
    );
  end if;
  raise exception 'Action inconnue';
end $$;

create function public.beta_capsule_photos(action text, capsule_id uuid, details jsonb default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select jadis_private.capsule_photos(action, capsule_id, details)
$$;
revoke all on function jadis_private.capsule_photos(text,uuid,jsonb),
  public.beta_capsule_photos(text,uuid,jsonb) from public, anon, authenticated;
grant execute on function jadis_private.capsule_photos(text,uuid,jsonb),
  public.beta_capsule_photos(text,uuid,jsonb) to authenticated;

commit;
