-- Gateway REST server-side para o schema privado.
-- As tabelas continuam fora do Data API; apenas estas funções prefixadas
-- ficam acessíveis ao worker/painel quando usados com service_role.

create or replace function public.lab_automatizado_heartbeat_worker(
  p_worker_id text,
  p_version text,
  p_capabilities jsonb
)
returns void
language plpgsql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
begin
  insert into lab_automatizado.workers (
    worker_id, status, capabilities, version, last_heartbeat_at, updated_at
  ) values (
    p_worker_id, 'online', coalesce(p_capabilities, '[]'::jsonb), p_version, now(), now()
  )
  on conflict (worker_id) do update set
    status = 'online',
    capabilities = excluded.capabilities,
    version = excluded.version,
    last_heartbeat_at = now(),
    updated_at = now();
end;
$$;

create or replace function public.lab_automatizado_enqueue_run(
  p_run_key text,
  p_run_type text,
  p_dataset_manifest text,
  p_config jsonb,
  p_requested_by text
)
returns uuid
language plpgsql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
declare
  v_run_id uuid;
begin
  if p_run_type not in ('quality_benchmark', 'research') then
    raise exception 'run_type_not_allowed';
  end if;

  insert into lab_automatizado.runs (
    run_key, run_type, dataset_manifest, config, requested_by
  ) values (
    p_run_key, p_run_type, p_dataset_manifest, coalesce(p_config, '{}'::jsonb), p_requested_by
  ) returning id into v_run_id;

  insert into lab_automatizado.commands (
    run_id, command_type, idempotency_key, payload, requested_by
  ) values (
    v_run_id,
    'start_run',
    p_run_key || ':start',
    jsonb_build_object('run_type', p_run_type, 'dataset_manifest', p_dataset_manifest),
    p_requested_by
  );

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'run_queued', 'Execução colocada na fila.', jsonb_build_object('run_key', p_run_key));

  return v_run_id;
end;
$$;

create or replace function public.lab_automatizado_claim_next_command(p_worker_id text)
returns table (
  command_id uuid,
  run_id uuid,
  command_type text,
  payload jsonb,
  idempotency_key text
)
language sql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
  select * from lab_automatizado.claim_next_command(p_worker_id);
$$;

create or replace function public.lab_automatizado_finish_command(
  p_command_id uuid,
  p_worker_id text,
  p_command_status text,
  p_run_status text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
declare
  v_run_id uuid;
begin
  if p_command_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'command_status_not_allowed';
  end if;
  if p_run_status not in ('succeeded', 'failed', 'cancelled') then
    raise exception 'run_status_not_allowed';
  end if;

  update lab_automatizado.commands
     set status = p_command_status,
         error_message = case when p_command_status = 'failed' then p_message else null end,
         completed_at = now()
   where id = p_command_id
     and claimed_by = p_worker_id
     and status = 'claimed'
   returning run_id into v_run_id;

  if v_run_id is null then
    raise exception 'command_not_owned_or_not_claimed';
  end if;

  update lab_automatizado.runs
     set status = p_run_status,
         error_message = case when p_run_status = 'failed' then p_message else null end,
         finished_at = now(),
         heartbeat_at = now(),
         updated_at = now()
   where id = v_run_id;

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'run_finished', coalesce(p_message, 'Execução finalizada.'), jsonb_build_object('status', p_run_status));

  update lab_automatizado.workers
     set status = 'online', last_heartbeat_at = now(), updated_at = now()
   where worker_id = p_worker_id;
end;
$$;

create or replace function public.lab_automatizado_list_runs(p_limit integer default 50)
returns setof lab_automatizado.runs
language sql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
  select *
    from lab_automatizado.runs
   order by created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

revoke all on function public.lab_automatizado_heartbeat_worker(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_claim_next_command(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_finish_command(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_list_runs(integer) from public, anon, authenticated;

grant execute on function public.lab_automatizado_heartbeat_worker(text, text, jsonb) to service_role;
grant execute on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) to service_role;
grant execute on function public.lab_automatizado_claim_next_command(text) to service_role;
grant execute on function public.lab_automatizado_finish_command(uuid, text, text, text, text) to service_role;
grant execute on function public.lab_automatizado_list_runs(integer) to service_role;
