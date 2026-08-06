-- Transporta a configuracao congelada do run ate o worker.
-- O worker continua aceitando somente tipos explicitamente implementados.

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
  v_config jsonb := coalesce(p_config, '{}'::jsonb);
begin
  if p_run_type not in ('quality_benchmark', 'research') then
    raise exception 'run_type_not_allowed';
  end if;

  insert into lab_automatizado.runs (
    run_key, run_type, dataset_manifest, config, requested_by
  ) values (
    p_run_key, p_run_type, p_dataset_manifest, v_config, p_requested_by
  ) returning id into v_run_id;

  insert into lab_automatizado.commands (
    run_id, command_type, idempotency_key, payload, requested_by
  ) values (
    v_run_id,
    'start_run',
    p_run_key || ':start',
    jsonb_build_object(
      'run_type', p_run_type,
      'dataset_manifest', p_dataset_manifest,
      'config', v_config
    ),
    p_requested_by
  );

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (
    v_run_id,
    'run_queued',
    'Execucao colocada na fila.',
    jsonb_build_object('run_key', p_run_key, 'run_type', p_run_type)
  );

  return v_run_id;
end;
$$;

revoke all on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) to service_role;
