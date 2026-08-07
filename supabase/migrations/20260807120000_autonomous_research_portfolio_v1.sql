-- Ciclo autonomo de pesquisa do Laboratorio Automatizado.
-- O play habilita somente a descoberta e os backtests brutos de development.
-- Validacao fora da amostra, portfolio e operacao continuam com gate humano.

create table if not exists lab_automatizado.lab_control (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  mode text not null default 'paused' check (mode in ('paused', 'autonomous_development')),
  max_concurrent_runs integer not null default 1 check (max_concurrent_runs between 1 and 2),
  max_variants_per_hypothesis integer not null default 500 check (max_variants_per_hypothesis between 1 and 500),
  max_generations integer not null default 5 check (max_generations between 1 and 5),
  max_strategies_per_asset integer not null default 5 check (max_strategies_per_asset between 1 and 5),
  target_monthly_pnl_per_contract numeric not null default 1000,
  diagnostic_band_low numeric not null default 700,
  diagnostic_band_high numeric not null default 1300,
  max_drawdown_per_contract numeric not null default 5000,
  last_cycle_at timestamptz,
  last_error text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into lab_automatizado.lab_control (id)
values (true)
on conflict (id) do nothing;

drop trigger if exists lab_control_set_updated_at on lab_automatizado.lab_control;
create trigger lab_control_set_updated_at
before update on lab_automatizado.lab_control
for each row execute function lab_automatizado.set_updated_at();

alter table lab_automatizado.hypotheses
  add column if not exists autonomous_status text not null default 'eligible'
  check (autonomous_status in ('eligible', 'search_ready', 'queued', 'running', 'candidate_ready', 'blocked'));

alter table lab_automatizado.hypothesis_test_runs
  add column if not exists variant_index integer not null default 0 check (variant_index between 0 and 499);

alter table lab_automatizado.hypothesis_test_runs
  drop constraint if exists hypothesis_test_runs_hypothesis_id_phase_generation_key;

create unique index if not exists hypothesis_test_runs_variant_unique
  on lab_automatizado.hypothesis_test_runs (hypothesis_id, phase, generation, variant_index);

create table if not exists lab_automatizado.research_queue (
  id uuid primary key default gen_random_uuid(),
  hypothesis_id uuid not null references lab_automatizado.hypotheses(id) on delete cascade,
  asset text not null check (asset in ('WDOFUT', 'WINFUT')),
  generation integer not null check (generation between 0 and 4),
  variant_index integer not null check (variant_index between 0 and 499),
  run_id uuid unique references lab_automatizado.runs(id) on delete set null,
  status text not null default 'ready' check (status in ('ready', 'queued', 'running', 'succeeded', 'failed', 'cancelled', 'skipped')),
  config jsonb not null,
  metrics jsonb not null default '{}'::jsonb,
  requested_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hypothesis_id, generation, variant_index)
);

create index if not exists research_queue_ready_idx
  on lab_automatizado.research_queue (status, created_at);

create table if not exists lab_automatizado.strategy_candidates (
  id uuid primary key default gen_random_uuid(),
  candidate_key text not null unique,
  asset text not null check (asset in ('WDOFUT', 'WINFUT')),
  hypothesis_id uuid references lab_automatizado.hypotheses(id) on delete set null,
  source_run_id uuid not null unique references lab_automatizado.runs(id) on delete cascade,
  status text not null default 'development_candidate' check (status in (
    'development_candidate', 'validation_pending', 'validated',
    'portfolio_candidate', 'portfolio_active', 'rejected', 'retired'
  )),
  generation integer not null default 0 check (generation between 0 and 4),
  variant_index integer not null default 0 check (variant_index between 0 and 499),
  metrics jsonb not null default '{}'::jsonb,
  monthly_series jsonb not null default '{}'::jsonb,
  artifact_uri text,
  evaluator_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists strategy_candidates_asset_status_idx
  on lab_automatizado.strategy_candidates (asset, status, created_at desc);

create table if not exists lab_automatizado.portfolio_members (
  id uuid primary key default gen_random_uuid(),
  asset text not null check (asset in ('WDOFUT', 'WINFUT')),
  slot integer not null check (slot between 1 and 5),
  candidate_id uuid not null references lab_automatizado.strategy_candidates(id) on delete restrict,
  status text not null default 'pending_human' check (status in ('pending_human', 'active', 'removed')),
  correlation_report jsonb not null default '{}'::jsonb,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (asset, slot),
  unique (asset, candidate_id)
);

create index if not exists portfolio_members_asset_idx
  on lab_automatizado.portfolio_members (asset, status, slot);

alter table lab_automatizado.lab_control enable row level security;
alter table lab_automatizado.research_queue enable row level security;
alter table lab_automatizado.strategy_candidates enable row level security;
alter table lab_automatizado.portfolio_members enable row level security;

revoke all on lab_automatizado.lab_control from public, anon, authenticated;
revoke all on lab_automatizado.research_queue from public, anon, authenticated;
revoke all on lab_automatizado.strategy_candidates from public, anon, authenticated;
revoke all on lab_automatizado.portfolio_members from public, anon, authenticated;
grant select, insert, update, delete on lab_automatizado.lab_control to service_role;
grant select, insert, update, delete on lab_automatizado.research_queue to service_role;
grant select, insert, update, delete on lab_automatizado.strategy_candidates to service_role;
grant select, insert, update, delete on lab_automatizado.portfolio_members to service_role;

create or replace function public.lab_automatizado_get_lab_control()
returns lab_automatizado.lab_control
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_control lab_automatizado.lab_control;
begin
  select * into v_control from lab_automatizado.lab_control where id = true;
  return v_control;
end;
$$;

create or replace function public.lab_automatizado_set_lab_control(
  p_enabled boolean,
  p_requested_by text
)
returns lab_automatizado.lab_control
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_control lab_automatizado.lab_control;
begin
  update lab_automatizado.lab_control
     set enabled = coalesce(p_enabled, false),
         mode = case when coalesce(p_enabled, false) then 'autonomous_development' else 'paused' end,
         last_error = null,
         updated_by = nullif(trim(coalesce(p_requested_by, '')), ''),
         updated_at = now()
   where id = true
   returning * into v_control;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    'hermes-supervisor',
    case when coalesce(p_enabled, false) then 'autonomous_lab_started' else 'autonomous_lab_paused' end,
    case when coalesce(p_enabled, false) then 'Ciclo autonomo de desenvolvimento iniciado.' else 'Ciclo autonomo de desenvolvimento pausado.' end,
    jsonb_build_object('requested_by', p_requested_by, 'enabled', coalesce(p_enabled, false))
  );
  return v_control;
end;
$$;

create or replace function public.lab_automatizado_list_candidates(p_asset text default null, p_limit integer default 100)
returns setof lab_automatizado.strategy_candidates
language sql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
  select *
    from lab_automatizado.strategy_candidates
   where p_asset is null or asset = p_asset
   order by created_at desc
   limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;

create or replace function public.lab_automatizado_list_portfolio(p_asset text default null)
returns table (
  slot integer,
  asset text,
  candidate_id uuid,
  candidate_key text,
  candidate_status text,
  metrics jsonb,
  correlation_report jsonb,
  approved_by text,
  approved_at timestamptz
)
language sql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
  select p.slot, p.asset, p.candidate_id, c.candidate_key, c.status,
         c.metrics, p.correlation_report, p.approved_by, p.approved_at
    from lab_automatizado.portfolio_members p
    join lab_automatizado.strategy_candidates c on c.id = p.candidate_id
   where p_asset is null or p.asset = p_asset
   order by p.asset, p.slot;
$$;

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
begin
  select * into v_control from lab_automatizado.lab_control where id = true;
  if not coalesce(v_control.enabled, false) then
    return 0;
  end if;

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

  if exists (select 1 from lab_automatizado.research_queue where hypothesis_id = v_hypothesis.id) then
    return (select count(*)::integer from lab_automatizado.research_queue where hypothesis_id = v_hypothesis.id);
  end if;

  -- A human-approved baseline already occupies variant zero. The autonomous
  -- grid starts at one in that case, preserving both paths idempotently.
  if exists (
    select 1 from lab_automatizado.hypothesis_test_runs
     where hypothesis_id = v_hypothesis.id and phase = 'development' and generation = 0
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
            if v_index < v_start_index or v_index > v_control.max_variants_per_hypothesis then
              continue;
            end if;

            v_generation := least(
              v_control.max_generations - 1,
              floor(v_index::numeric / greatest(1, ceil(v_control.max_variants_per_hypothesis::numeric / v_control.max_generations)))::integer
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
              'phase', 'development',
              'train_start', '2012-04-01T00:00:00',
              'train_end_exclusive', '2023-01-01T00:00:00',
              'evaluation_start', '2012-04-01T00:00:00',
              'evaluation_end_exclusive', '2023-01-01T00:00:00',
              'generation', v_generation,
              'variant_index', v_index,
              'max_variants', v_control.max_variants_per_hypothesis,
              'max_seconds', 7200,
              'execution_spec', v_spec,
              'pricing_policy', 'gross_only',
              'costs_applied', false,
              'slippage_applied', false,
              'holdout_accessed', false,
              'holdout_policy', '2025_plus_locked_except_preregistered_probe_months',
              'dataset_manifest', 'development-full-v1'
            );
            insert into lab_automatizado.research_queue
              (hypothesis_id, asset, generation, variant_index, status, config, requested_by)
            values
              (v_hypothesis.id, v_hypothesis.asset, v_generation, v_index, 'ready', v_config, p_requested_by)
            on conflict (hypothesis_id, generation, variant_index) do nothing;
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
    'Grade deterministica de variantes preparada para desenvolvimento.',
    jsonb_build_object('hypothesis_id', v_hypothesis.id, 'variants', v_inserted,
                       'max_generations', v_control.max_generations, 'max_variants', v_control.max_variants_per_hypothesis)
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

  select q.* into v_item
    from lab_automatizado.research_queue q
    join lab_automatizado.hypotheses h on h.id = q.hypothesis_id
   where q.status = 'ready' and h.status in ('proposed', 'approved_for_test')
   order by q.created_at, q.variant_index
   for update of q skip locked
   limit 1;

  if v_item.id is null then
    return jsonb_build_object('queued', false, 'reason', 'empty');
  end if;

  select * into v_hypothesis from lab_automatizado.hypotheses where id = v_item.hypothesis_id;
  v_run_key := v_hypothesis.hypothesis_key || ':g' || v_item.generation::text || ':v' || lpad(v_item.variant_index::text, 3, '0');

  insert into lab_automatizado.runs (run_key, run_type, dataset_manifest, config, requested_by)
  values (v_run_key, 'strategy_backtest', 'development-full-v1', v_item.config, coalesce(p_requested_by, 'autonomous-orchestrator'))
  on conflict (run_key) do update set run_key = excluded.run_key
  returning id into v_run_id;
  if v_run_id is null then
    select id into v_run_id from lab_automatizado.runs where run_key = v_run_key;
  end if;

  insert into lab_automatizado.commands (run_id, command_type, idempotency_key, payload, requested_by)
  values (
    v_run_id, 'start_run', v_run_key || ':start',
    jsonb_build_object('run_type', 'strategy_backtest', 'dataset_manifest', 'development-full-v1', 'config', v_item.config),
    coalesce(p_requested_by, 'autonomous-orchestrator')
  ) on conflict (idempotency_key) do nothing;

  update lab_automatizado.research_queue
     set status = 'queued', run_id = v_run_id, updated_at = now()
   where id = v_item.id;
  update lab_automatizado.hypotheses
     set autonomous_status = 'queued', updated_at = now()
   where id = v_item.hypothesis_id;
  insert into lab_automatizado.hypothesis_test_runs
    (hypothesis_id, run_id, phase, generation, variant_index, variant_budget, time_budget_seconds)
  values (v_item.hypothesis_id, v_run_id, 'development', v_item.generation, v_item.variant_index,
          v_control.max_variants_per_hypothesis, 7200)
  on conflict (hypothesis_id, phase, generation, variant_index) do nothing;
  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'autonomous_variant_queued', 'Variante autonoma de desenvolvimento enfileirada.',
          jsonb_build_object('hypothesis_id', v_item.hypothesis_id, 'generation', v_item.generation,
                             'variant_index', v_item.variant_index));
  return jsonb_build_object('queued', true, 'run_id', v_run_id, 'hypothesis_id', v_item.hypothesis_id,
                            'generation', v_item.generation, 'variant_index', v_item.variant_index);
end;
$$;

create or replace function public.lab_automatizado_register_candidate(
  p_source_run_id uuid,
  p_candidate_key text,
  p_asset text,
  p_hypothesis_id uuid,
  p_generation integer,
  p_variant_index integer,
  p_metrics jsonb,
  p_monthly_series jsonb,
  p_artifact_uri text,
  p_evaluator_version text
)
returns lab_automatizado.strategy_candidates
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_candidate lab_automatizado.strategy_candidates;
begin
  insert into lab_automatizado.strategy_candidates
    (candidate_key, asset, hypothesis_id, source_run_id, generation, variant_index,
     metrics, monthly_series, artifact_uri, evaluator_version)
  values
    (p_candidate_key, p_asset, p_hypothesis_id, p_source_run_id, coalesce(p_generation, 0), coalesce(p_variant_index, 0),
     coalesce(p_metrics, '{}'::jsonb), coalesce(p_monthly_series, '{}'::jsonb), p_artifact_uri,
     coalesce(p_evaluator_version, 'candidate-evaluator-v1'))
  on conflict (source_run_id) do update set
    metrics = excluded.metrics,
    monthly_series = excluded.monthly_series,
    artifact_uri = excluded.artifact_uri,
    updated_at = now()
  returning * into v_candidate;

  update lab_automatizado.research_queue
     set status = 'succeeded', metrics = coalesce(p_metrics, '{}'::jsonb), updated_at = now()
   where run_id = p_source_run_id;
  update lab_automatizado.hypotheses
     set autonomous_status = 'candidate_ready', updated_at = now()
   where id = p_hypothesis_id;
  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values ('hermes-supervisor', 'strategy_candidate_registered',
          'Candidato bruto registrado; promocao permanece humana.',
          jsonb_build_object('candidate_id', v_candidate.id, 'source_run_id', p_source_run_id,
                             'asset', p_asset, 'candidate_key', p_candidate_key));
  return v_candidate;
end;
$$;

-- Mantem a fila sincronizada mesmo quando o run e finalizado pelo worker.
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
         updated_at = now()
   where run_id = new.id;
  return new;
end;
$$;

drop trigger if exists runs_sync_research_queue on lab_automatizado.runs;
create trigger runs_sync_research_queue
after update of status on lab_automatizado.runs
for each row execute function lab_automatizado.sync_research_queue_status();

revoke all on function public.lab_automatizado_get_lab_control() from public, anon, authenticated;
revoke all on function public.lab_automatizado_set_lab_control(boolean, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_list_candidates(text, integer) from public, anon, authenticated;
revoke all on function public.lab_automatizado_list_portfolio(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_prepare_hypothesis_search(uuid, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_queue_next_variant(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_register_candidate(uuid, text, text, uuid, integer, integer, jsonb, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_get_lab_control() to service_role;
grant execute on function public.lab_automatizado_set_lab_control(boolean, text) to service_role;
grant execute on function public.lab_automatizado_list_candidates(text, integer) to service_role;
grant execute on function public.lab_automatizado_list_portfolio(text) to service_role;
grant execute on function public.lab_automatizado_prepare_hypothesis_search(uuid, text) to service_role;
grant execute on function public.lab_automatizado_queue_next_variant(text) to service_role;
grant execute on function public.lab_automatizado_register_candidate(uuid, text, text, uuid, integer, integer, jsonb, jsonb, text, text) to service_role;
