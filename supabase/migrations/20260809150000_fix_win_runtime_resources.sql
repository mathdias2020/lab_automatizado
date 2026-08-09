-- Runtime V2: aumentar o orçamento de execução do backtest e manter o
-- heartbeat vivo enquanto o DuckDB processa um lote longo.

alter table lab_automatizado.lab_control
  drop constraint if exists lab_control_run_timeout_check,
  add constraint lab_control_run_timeout_check check (run_timeout_seconds between 300 and 14400);

alter table lab_automatizado.hypothesis_test_runs
  drop constraint if exists hypothesis_test_runs_time_budget_seconds_check,
  add constraint hypothesis_test_runs_time_budget_seconds_check check (time_budget_seconds between 60 and 14400);

update lab_automatizado.lab_control
   set run_timeout_seconds = 14400,
       updated_at = now()
 where id = true;

update lab_automatizado.research_queue
   set config = jsonb_set(config, '{max_seconds}', '14400'::jsonb, true),
       updated_at = now()
 where status in ('ready', 'queued')
   and search_stage in ('screening', 'full')
   and coalesce((config->>'max_seconds')::integer, 0) < 14400;

update lab_automatizado.hypothesis_test_runs
   set time_budget_seconds = 14400
 where phase in ('screening', 'development')
   and run_id in (
     select id
       from lab_automatizado.runs
      where status in ('queued', 'claimed', 'running')
   )
   and time_budget_seconds < 14400;

create or replace function public.lab_automatizado_heartbeat_run(
  p_run_id uuid,
  p_worker_id text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
begin
  update lab_automatizado.runs
     set heartbeat_at = now(),
         updated_at = now()
   where id = p_run_id
     and worker_id = p_worker_id
     and status in ('claimed', 'running');

  if not found then
    raise exception 'run_not_owned_or_not_active';
  end if;

  update lab_automatizado.workers
     set status = 'busy',
         last_heartbeat_at = now(),
         updated_at = now()
   where worker_id = p_worker_id;
end;
$$;

revoke all on function public.lab_automatizado_heartbeat_run(uuid, text)
  from public, anon, authenticated;
grant execute on function public.lab_automatizado_heartbeat_run(uuid, text)
  to service_role;
