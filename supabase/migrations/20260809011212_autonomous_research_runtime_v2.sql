-- Runtime V2 do ciclo autônomo.
--
-- Esta migração não apaga a auditoria da primeira execução. As filas antigas
-- recebem search_stage = legacy e deixam de ser elegíveis para novos runs.
-- A nova busca começa em screening, promove apenas os melhores resultados
-- determinísticos para o desenvolvimento completo e mantém holdout bloqueado.

alter table lab_automatizado.lab_control
  add column if not exists screening_enabled boolean not null default true,
  add column if not exists screening_max_variants_per_hypothesis integer not null default 96,
  add column if not exists screening_start_exclusive timestamptz not null default '2018-01-01T00:00:00Z',
  add column if not exists screening_end_exclusive timestamptz not null default '2023-01-01T00:00:00Z',
  add column if not exists screening_top_n integer not null default 8,
  add column if not exists run_timeout_seconds integer not null default 7200,
  add column if not exists last_scheduled_asset text;

alter table lab_automatizado.lab_control
  drop constraint if exists lab_control_screening_max_variants_check,
  drop constraint if exists lab_control_screening_top_n_check,
  drop constraint if exists lab_control_run_timeout_check,
  add constraint lab_control_screening_max_variants_check check (screening_max_variants_per_hypothesis between 1 and 500),
  add constraint lab_control_screening_top_n_check check (screening_top_n between 1 and 50),
  add constraint lab_control_run_timeout_check check (run_timeout_seconds between 300 and 14400);

update lab_automatizado.lab_control
   set screening_enabled = true,
       screening_max_variants_per_hypothesis = least(greatest(screening_max_variants_per_hypothesis, 1), 96),
       screening_start_exclusive = '2018-01-01T00:00:00Z',
       screening_end_exclusive = '2023-01-01T00:00:00Z',
       screening_top_n = least(greatest(screening_top_n, 1), 8),
       run_timeout_seconds = 7200
 where id = true;

alter table lab_automatizado.runs
  add column if not exists search_stage text not null default 'legacy',
  add column if not exists failure_category text;

alter table lab_automatizado.commands
  add column if not exists failure_category text;

alter table lab_automatizado.research_queue
  add column if not exists search_stage text not null default 'legacy',
  add column if not exists failure_category text;

alter table lab_automatizado.research_queue
  drop constraint if exists research_queue_hypothesis_id_generation_variant_index_key;

create unique index if not exists research_queue_variant_stage_unique
  on lab_automatizado.research_queue (hypothesis_id, generation, variant_index, search_stage);

create index if not exists research_queue_active_stage_idx
  on lab_automatizado.research_queue (search_stage, status, asset, created_at);

alter table lab_automatizado.runs
  drop constraint if exists runs_failure_category_check,
  add constraint runs_failure_category_check check (
    failure_category is null or failure_category in (
      'infra_timeout', 'infra_runner', 'infra_permission', 'infra_artifact',
      'validation', 'cancelled_reconfiguration', 'superseded', 'unknown'
    )
  );

alter table lab_automatizado.commands
  drop constraint if exists commands_failure_category_check,
  add constraint commands_failure_category_check check (
    failure_category is null or failure_category in (
      'infra_timeout', 'infra_runner', 'infra_permission', 'infra_artifact',
      'validation', 'cancelled_reconfiguration', 'superseded', 'unknown'
    )
  );

alter table lab_automatizado.research_queue
  drop constraint if exists research_queue_failure_category_check,
  add constraint research_queue_failure_category_check check (
    failure_category is null or failure_category in (
      'infra_timeout', 'infra_runner', 'infra_permission', 'infra_artifact',
      'validation', 'cancelled_reconfiguration', 'superseded', 'unknown'
    )
  );

create or replace function public.lab_automatizado_prepare_hypothesis_search(
  p_hypothesis_id uuid,
  p_requested_by text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_hypothesis lab_automatizado.hypotheses;
  v_base_spec jsonb;
  v_spec jsonb;
  v_config jsonb;
  v_inserted integer := 0;
  v_index integer := 0;
  v_start_index integer := 0;
  v_generation integer;
  v_control lab_automatizado.lab_control;
  v_aggression numeric;
  v_move numeric;
  v_stop integer;
  v_target integer;
  v_time_stop integer;
  v_stage text;
  v_variant_cap integer;
  v_start text;
  v_end text;
begin
  select * into v_control from lab_automatizado.lab_control where id = true;

  select * into v_hypothesis
    from lab_automatizado.hypotheses
   where id = p_hypothesis_id
   for update;

  if v_hypothesis.id is null
     or v_hypothesis.status not in ('proposed', 'approved_for_test')
     or v_hypothesis.asset not in ('WDOFUT', 'WINFUT')
     or v_hypothesis.executable_contract_version <> 'hermes_execution_v2'
     or jsonb_typeof(v_hypothesis.payload->'execution_spec') <> 'object' then
    return 0;
  end if;

  v_stage := case when coalesce(v_control.screening_enabled, true) then 'screening' else 'full' end;
  v_variant_cap := case
    when v_stage = 'screening' then least(v_control.max_variants_per_hypothesis, v_control.screening_max_variants_per_hypothesis)
    else v_control.max_variants_per_hypothesis
  end;
  v_start := case when v_stage = 'screening'
    then to_char(v_control.screening_start_exclusive at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
    else '2012-04-01T00:00:00' end;
  v_end := case when v_stage = 'screening'
    then to_char(v_control.screening_end_exclusive at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
    else '2023-01-01T00:00:00' end;

  if exists (
    select 1 from lab_automatizado.research_queue
     where hypothesis_id = v_hypothesis.id
       and search_stage = v_stage
       and status not in ('skipped', 'cancelled')
  ) then
    return (
      select count(*)::integer from lab_automatizado.research_queue
       where hypothesis_id = v_hypothesis.id and search_stage = v_stage
    );
  end if;

  if exists (
    select 1 from lab_automatizado.hypothesis_test_runs
     where hypothesis_id = v_hypothesis.id and phase in ('development', 'screening') and generation = 0
  ) then
    v_start_index := 1;
  end if;

  v_base_spec := v_hypothesis.payload->'execution_spec';
  foreach v_aggression in array array[0.90::numeric, 0.95::numeric, 0.975::numeric, 0.99::numeric] loop
    foreach v_move in array array[0.25::numeric, 0.50::numeric, 0.75::numeric] loop
      foreach v_stop in array array[10, 20, 30] loop
        foreach v_target in array array[20, 40, 60, 80] loop
          foreach v_time_stop in array array[5, 15, 30] loop
            v_index := v_index + 1;
            if v_index < v_start_index or v_index > v_variant_cap then
              continue;
            end if;

            v_generation := least(
              v_control.max_generations - 1,
              floor(v_index::numeric / greatest(1, ceil(v_variant_cap::numeric / v_control.max_generations)))::integer
            );
            v_spec := jsonb_set(v_base_spec, '{feature,aggression_quantile}', to_jsonb(v_aggression), true);
            v_spec := jsonb_set(v_spec, '{feature,absorption_move_quantile}', to_jsonb(v_move), true);
            v_spec := jsonb_set(v_spec, '{exit,stop_ticks}', to_jsonb(v_stop), true);
            v_spec := jsonb_set(v_spec, '{exit,target_ticks}', to_jsonb(v_target), true);
            v_spec := jsonb_set(v_spec, '{exit,time_stop_minutes}', to_jsonb(v_time_stop), true);
            v_config := jsonb_build_object(
              'executor_id', 'strategy_backtest_v1',
              'version', '1.0.0',
              'hypothesis_id', v_hypothesis.id,
              'hypothesis_key', v_hypothesis.hypothesis_key,
              'asset', v_hypothesis.asset,
              'phase', case when v_stage = 'screening' then 'screening' else 'development' end,
              'search_stage', v_stage,
              'train_start', v_start,
              'train_end_exclusive', v_end,
              'evaluation_start', v_start,
              'evaluation_end_exclusive', v_end,
              'generation', v_generation,
              'variant_index', v_index,
              'max_variants', v_variant_cap,
              'max_seconds', v_control.run_timeout_seconds,
              'execution_spec', v_spec,
              'pricing_policy', 'gross_only',
              'costs_applied', false,
              'slippage_applied', false,
              'holdout_accessed', false,
              'holdout_policy', '2025_plus_locked_except_preregistered_probe_months',
              'dataset_manifest', case when v_stage = 'screening' then 'development-screening-v2' else 'development-full-v1' end
            );
            insert into lab_automatizado.research_queue
              (hypothesis_id, asset, generation, variant_index, search_stage, status, config, requested_by)
            values
              (v_hypothesis.id, v_hypothesis.asset, v_generation, v_index, v_stage, 'ready', v_config, p_requested_by)
            on conflict (hypothesis_id, generation, variant_index, search_stage) do nothing;
            v_inserted := v_inserted + 1;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;

  update lab_automatizado.hypotheses
     set autonomous_status = case when v_inserted > 0 then 'search_ready' else autonomous_status end,
         updated_at = now()
   where id = v_hypothesis.id;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    'hermes-supervisor', 'hypothesis_search_prepared',
    'Triagem determinística de variantes preparada; o desenvolvimento completo fica reservado aos melhores resultados.',
    jsonb_build_object('hypothesis_id', v_hypothesis.id, 'variants', v_inserted,
                       'search_stage', v_stage, 'max_generations', v_control.max_generations,
                       'max_variants', v_variant_cap, 'screening_start', v_start, 'screening_end', v_end)
  );
  return v_inserted;
end;
$$;

create or replace function public.lab_automatizado_queue_next_variant(p_requested_by text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_control lab_automatizado.lab_control;
  v_item lab_automatizado.research_queue;
  v_hypothesis lab_automatizado.hypotheses;
  v_active integer;
  v_run_id uuid;
  v_run_key text;
  v_preferred_asset text;
begin
  select * into v_control from lab_automatizado.lab_control where id = true;
  if not coalesce(v_control.enabled, false) then
    return jsonb_build_object('queued', false, 'reason', 'paused');
  end if;

  select count(*)::integer into v_active
    from lab_automatizado.runs
   where run_type = 'strategy_backtest' and status in ('queued', 'claimed', 'running');
  if v_active >= v_control.max_concurrent_runs then
    return jsonb_build_object('queued', false, 'reason', 'capacity');
  end if;

  v_preferred_asset := case when v_control.last_scheduled_asset = 'WDOFUT' then 'WINFUT' else 'WDOFUT' end;
  select q.* into v_item
    from lab_automatizado.research_queue q
    join lab_automatizado.hypotheses h on h.id = q.hypothesis_id
   where q.status = 'ready'
     and q.search_stage in ('screening', 'full')
     and h.status in ('proposed', 'approved_for_test')
     and h.executable_contract_version = 'hermes_execution_v2'
     and jsonb_typeof(h.payload->'execution_spec') = 'object'
   order by case when q.asset = v_preferred_asset then 0 else 1 end,
            case when q.search_stage = 'screening' then 0 else 1 end,
            q.created_at, q.variant_index
   for update of q skip locked
   limit 1;

  if v_item.id is null then
    return jsonb_build_object('queued', false, 'reason', 'empty');
  end if;

  select * into v_hypothesis from lab_automatizado.hypotheses where id = v_item.hypothesis_id;
  v_run_key := v_hypothesis.hypothesis_key || ':' || v_item.search_stage || ':g' || v_item.generation::text || ':v' || lpad(v_item.variant_index::text, 3, '0');

  insert into lab_automatizado.runs
    (run_key, run_type, dataset_manifest, config, requested_by, search_stage)
  values (v_run_key, 'strategy_backtest', v_item.config->>'dataset_manifest', v_item.config, coalesce(p_requested_by, 'autonomous-orchestrator'), v_item.search_stage)
  on conflict (run_key) do update set run_key = excluded.run_key
  returning id into v_run_id;
  if v_run_id is null then
    select id into v_run_id from lab_automatizado.runs where run_key = v_run_key;
  end if;

  insert into lab_automatizado.commands (run_id, command_type, idempotency_key, payload, requested_by)
  values (
    v_run_id, 'start_run', v_run_key || ':start',
    jsonb_build_object('run_type', 'strategy_backtest', 'dataset_manifest', v_item.config->>'dataset_manifest', 'config', v_item.config),
    coalesce(p_requested_by, 'autonomous-orchestrator')
  ) on conflict (idempotency_key) do nothing;

  update lab_automatizado.research_queue
     set status = 'queued', run_id = v_run_id, updated_at = now()
   where id = v_item.id;
  update lab_automatizado.lab_control
     set last_scheduled_asset = v_item.asset, updated_at = now()
   where id = true;
  update lab_automatizado.hypotheses
     set autonomous_status = 'queued', updated_at = now()
   where id = v_item.hypothesis_id;
  insert into lab_automatizado.hypothesis_test_runs
    (hypothesis_id, run_id, phase, generation, variant_index, variant_budget, time_budget_seconds)
  values (v_item.hypothesis_id, v_run_id, v_item.search_stage, v_item.generation, v_item.variant_index,
          v_control.max_variants_per_hypothesis, v_control.run_timeout_seconds)
  on conflict (hypothesis_id, phase, generation, variant_index) do nothing;
  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'autonomous_variant_queued', 'Variante autônoma enfileirada com distribuição por ativo.',
          jsonb_build_object('hypothesis_id', v_item.hypothesis_id, 'asset', v_item.asset,
                             'search_stage', v_item.search_stage, 'generation', v_item.generation,
                             'variant_index', v_item.variant_index));
  return jsonb_build_object('queued', true, 'run_id', v_run_id, 'hypothesis_id', v_item.hypothesis_id,
                            'asset', v_item.asset, 'search_stage', v_item.search_stage,
                            'generation', v_item.generation, 'variant_index', v_item.variant_index);
end;
$$;

create or replace function public.lab_automatizado_promote_screening_top(p_requested_by text)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_control lab_automatizado.lab_control;
  v_row record;
  v_config jsonb;
  v_inserted integer := 0;
begin
  select * into v_control from lab_automatizado.lab_control where id = true;
  for v_row in
    select q.*, row_number() over (
      partition by q.hypothesis_id
      order by coalesce(nullif(q.metrics->>'mean_monthly_pnl_per_contract', '')::numeric, -1000000000) desc,
               coalesce(nullif(q.metrics->>'positive_months', '')::numeric, 0) desc,
               q.variant_index
    ) as rank_in_hypothesis
      from lab_automatizado.research_queue q
      join lab_automatizado.hypotheses h on h.id = q.hypothesis_id
     where q.search_stage = 'screening'
       and q.status = 'succeeded'
       and h.executable_contract_version = 'hermes_execution_v2'
       and not exists (
         select 1 from lab_automatizado.research_queue active
          where active.hypothesis_id = q.hypothesis_id
            and active.search_stage = 'screening'
            and active.status in ('ready', 'queued', 'running')
       )
       and not exists (
         select 1 from lab_automatizado.research_queue full_queue
          where full_queue.hypothesis_id = q.hypothesis_id
            and full_queue.search_stage = 'full'
       )
  loop
    if v_row.rank_in_hypothesis > v_control.screening_top_n then
      continue;
    end if;
    v_config := v_row.config;
    v_config := jsonb_set(v_config, '{phase}', '"development"'::jsonb, true);
    v_config := jsonb_set(v_config, '{search_stage}', '"full"'::jsonb, true);
    v_config := jsonb_set(v_config, '{train_start}', '"2012-04-01T00:00:00"'::jsonb, true);
    v_config := jsonb_set(v_config, '{train_end_exclusive}', '"2023-01-01T00:00:00"'::jsonb, true);
    v_config := jsonb_set(v_config, '{evaluation_start}', '"2012-04-01T00:00:00"'::jsonb, true);
    v_config := jsonb_set(v_config, '{evaluation_end_exclusive}', '"2023-01-01T00:00:00"'::jsonb, true);
    v_config := jsonb_set(v_config, '{dataset_manifest}', '"development-full-v1"'::jsonb, true);
    v_config := jsonb_set(v_config, '{max_variants}', to_jsonb(v_control.max_variants_per_hypothesis), true);
    insert into lab_automatizado.research_queue
      (hypothesis_id, asset, generation, variant_index, search_stage, status, config, requested_by, metrics)
    values
      (v_row.hypothesis_id, v_row.asset, v_row.generation, v_row.variant_index, 'full', 'ready', v_config,
       coalesce(p_requested_by, 'autonomous-orchestrator'), v_row.metrics)
    on conflict (hypothesis_id, generation, variant_index, search_stage) do nothing;
    if found then v_inserted := v_inserted + 1; end if;
  end loop;

  if v_inserted > 0 then
    insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
    values ('hermes-supervisor', 'screening_promoted_to_full',
            'Os melhores resultados da triagem foram encaminhados para o desenvolvimento completo.',
            jsonb_build_object('variants', v_inserted, 'top_n', v_control.screening_top_n));
  end if;
  return v_inserted;
end;
$$;

create or replace function lab_automatizado.sync_research_queue_status()
returns trigger
language plpgsql
set search_path = pg_catalog, public, lab_automatizado
as $$
begin
  update lab_automatizado.research_queue
     set status = case new.status
       when 'queued' then 'queued'
       when 'claimed' then 'running'
       when 'running' then 'running'
       when 'succeeded' then 'succeeded'
       when 'failed' then 'failed'
       when 'cancelled' then 'cancelled'
       else status end,
         failure_category = new.failure_category,
         updated_at = now()
   where run_id = new.id;
  return new;
end;
$$;

drop trigger if exists runs_sync_research_queue on lab_automatizado.runs;
create trigger runs_sync_research_queue
after update of status, failure_category on lab_automatizado.runs
for each row execute function lab_automatizado.sync_research_queue_status();

drop function if exists public.lab_automatizado_finish_command(uuid, text, text, text, text);
create or replace function public.lab_automatizado_finish_command(
  p_command_id uuid,
  p_worker_id text,
  p_command_status text,
  p_run_status text,
  p_message text,
  p_failure_category text default null
)
returns void
language plpgsql
security definer
set search_path = public, lab_automatizado, pg_catalog
as $$
declare
  v_run_id uuid;
  v_category text := nullif(trim(coalesce(p_failure_category, '')), '');
begin
  if p_command_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'command_status_not_allowed';
  end if;
  if p_run_status not in ('succeeded', 'failed', 'cancelled') then
    raise exception 'run_status_not_allowed';
  end if;
  if v_category is not null and v_category not in (
    'infra_timeout', 'infra_runner', 'infra_permission', 'infra_artifact',
    'validation', 'cancelled_reconfiguration', 'superseded', 'unknown'
  ) then
    raise exception 'failure_category_not_allowed';
  end if;

  update lab_automatizado.commands
     set status = p_command_status,
         error_message = case when p_command_status = 'failed' then p_message else null end,
         failure_category = v_category,
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
         failure_category = v_category,
         finished_at = now(),
         heartbeat_at = now(),
         updated_at = now()
   where id = v_run_id;

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'run_finished', coalesce(p_message, 'Execução finalizada.'),
          jsonb_build_object('status', p_run_status, 'failure_category', v_category));

  update lab_automatizado.workers
     set status = 'online', last_heartbeat_at = now(), updated_at = now()
   where worker_id = p_worker_id;
end;
$$;

create or replace function public.lab_automatizado_get_lab_health()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'control', to_jsonb(c),
    'queue', coalesce((select jsonb_agg(to_jsonb(q) order by q.search_stage, q.asset, q.status)
      from (
        select search_stage, asset, status, count(*)::integer as count,
               min(created_at) as first_created, max(updated_at) as last_updated
        from lab_automatizado.research_queue
        group by search_stage, asset, status
      ) q), '[]'::jsonb),
    'runs_24h', coalesce((select jsonb_agg(to_jsonb(r) order by r.status, r.failure_category)
      from (
        select status, coalesce(failure_category, 'none') as failure_category, count(*)::integer as count
        from lab_automatizado.runs
        where created_at >= now() - interval '24 hours'
        group by status, coalesce(failure_category, 'none')
      ) r), '[]'::jsonb),
    'active_run', (select to_jsonb(a) from (
      select id, run_key, status, search_stage, config->>'asset' as asset,
             config->>'variant_index' as variant_index, created_at, heartbeat_at
      from lab_automatizado.runs
      where status in ('queued', 'claimed', 'running')
      order by created_at
      limit 1
    ) a),
    'worker', (select to_jsonb(w) from (
      select worker_id, status, version, last_heartbeat_at, updated_at
      from lab_automatizado.workers
      order by updated_at desc limit 1
    ) w)
  ) into v_result
  from lab_automatizado.lab_control c
  where c.id = true;
  return coalesce(v_result, '{}'::jsonb);
end;
$$;

revoke all on function public.lab_automatizado_prepare_hypothesis_search(uuid, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_queue_next_variant(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_promote_screening_top(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_get_lab_health() from public, anon, authenticated;
revoke all on function public.lab_automatizado_finish_command(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_prepare_hypothesis_search(uuid, text) to service_role;
grant execute on function public.lab_automatizado_queue_next_variant(text) to service_role;
grant execute on function public.lab_automatizado_promote_screening_top(text) to service_role;
grant execute on function public.lab_automatizado_get_lab_health() to service_role;
grant execute on function public.lab_automatizado_finish_command(uuid, text, text, text, text, text) to service_role;
