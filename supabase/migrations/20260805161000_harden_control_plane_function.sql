-- Endurece a função interna usada pelos triggers do control plane.
create or replace function lab_automatizado.set_updated_at()
returns trigger
language plpgsql
set search_path = lab_automatizado, pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke execute on function lab_automatizado.set_updated_at() from public, anon, authenticated;
grant execute on function lab_automatizado.set_updated_at() to service_role;
