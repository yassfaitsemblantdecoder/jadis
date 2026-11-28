do $$
begin
  if (select count(*) from jadis_private.directory_import_batches) <> 3
     or (select count(*) from jadis_private.directory_import_candidates) <> 3
     or (select count(*) from jadis_private.directory_import_rejections) <> 6 then
    raise exception 'Staging totals changed after replay or restore';
  end if;

  if not exists (
    select 1 from jadis_private.directory_import_batches
    where source = 'school' and row_count = 7 and duplicate_count = 1
      and candidate_count = 1 and rejected_count = 5
  ) or (select count(*) from jadis_private.directory_import_rejections
        where reason = 'identifier_conflict' and external_id = '0000002B') <> 2 then
    raise exception 'Duplicate or conflicting UAI was handled incorrectly';
  end if;

  if (select count(*) from jadis_private.directory_import_rejections
      where external_id = '0000005E' and reason in ('invalid_field_type','identifier_conflict')) <> 2 then
    raise exception 'A valid row sharing the identifier of an invalid row escaped quarantine';
  end if;

  if not exists (select 1 from jadis_private.directory_import_candidates
                 where external_id = '0000001A' and source_status = 'OUVERT')
     or not exists (select 1 from jadis_private.directory_import_candidates
                 where external_id = '0000003C' and closed_on = date '2000-02-01'
                   and name is null and needs_review)
     or not exists (select 1 from jadis_private.directory_import_candidates
                    where external_id = 'demo-01' and uai is null and kind = 'Université') then
    raise exception 'School status, closure date or Paysage identifier was lost';
  end if;

  if exists (select 1 from jadis_private.institutions)
     or exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'jadis_private' and c.relname like 'directory_import_%'
                  and c.relkind = 'r' and (not c.relrowsecurity
                    or has_table_privilege('anon', c.oid, 'select,insert,update,delete')
                    or has_table_privilege('authenticated', c.oid, 'select,insert,update,delete'))) then
    raise exception 'Staging exposed data or wrote into the canonical model';
  end if;
end $$;
\echo 'Directory staging checks passed.'
