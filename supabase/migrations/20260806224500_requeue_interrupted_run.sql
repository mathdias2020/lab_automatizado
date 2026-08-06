-- Recuperacao auditada de runs que terminaram por falha de infraestrutura ou
-- ficaram claimed apos a interrupcao do worker. Nao reabre runs bem-sucedidos.

create or replace function public.lab_automatizado_requeue_run(
  p_run_id uuid,
  p_requested_by text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_run lab_automatizado.runs;
  v_previous_error text;
  v_updated_commands integer;
  v_reason text := left(trim(coalesce(p_reason, '')), 2000);
begin
  if v_reason = '' then
    raise exception 'requeue_reason_required';
  end if;

  select * into v_run
    from lab_automatizado.runs
   where id = p_run_id
   for update;

  if v_run.id is null then
    raise exception 'run_not_found';
  end if;

  if v_run.status not in ('failed', 'claimed') then
    raise exception 'run_not_requeueable';
  end if;

  if v_run.status = 'claimed'
     and coalesce(v_run.heartbeat_at, v_run.updated_at) > now() - interval '5 minutes' then
    raise exception 'run_still_active';
  end if;

  v_previous_error := v_run.error_message;

  update lab_automatizado.commands
     set status = 'queued',
         claimed_by = null,
         claimed_at = null,
         completed_at = null,
         error_message = null
   where run_id = p_run_id
     and status in ('failed', 'claimed');

  get diagnostics v_updated_commands = row_count;
  if v_updated_commands = 0 then
    raise exception 'run_command_not_requeueable';
  end if;

  update lab_automatizado.runs
     set status = 'queued',
         worker_id = null,
         heartbeat_at = null,
         started_at = null,
         finished_at = null,
         error_message = null,
         updated_at = now()
   where id = p_run_id;

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (
    p_run_id,
    'run_requeued',
    'Execucao reencaminhada apos falha ou interrupcao de infraestrutura.',
    jsonb_build_object(
      'requested_by', p_requested_by,
      'reason', v_reason,
      'previous_status', v_run.status,
      'previous_error', v_previous_error
    )
  );

  return p_run_id;
end;
$$;

revoke all on function public.lab_automatizado_requeue_run(uuid, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_requeue_run(uuid, text, text) to service_role;
