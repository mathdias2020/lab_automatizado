-- Permite ao worker registrar somente artefatos do run que ele reivindicou.
create or replace function public.lab_automatizado_register_artifact(
  p_run_id uuid,
  p_worker_id text,
  p_artifact_type text,
  p_uri text,
  p_sha256 text,
  p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
declare
  v_artifact_id uuid;
begin
  if not exists (
    select 1
      from lab_automatizado.runs
     where id = p_run_id
       and worker_id = p_worker_id
  ) then
    raise exception 'run_not_owned_by_worker';
  end if;

  insert into lab_automatizado.artifacts (
    run_id, artifact_type, uri, sha256, metadata
  ) values (
    p_run_id, p_artifact_type, p_uri, p_sha256, coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_artifact_id;

  return v_artifact_id;
end;
$$;

revoke all on function public.lab_automatizado_register_artifact(uuid, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.lab_automatizado_register_artifact(uuid, text, text, text, text, jsonb) to service_role;
