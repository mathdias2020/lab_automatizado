-- Hermes Research V2: hipóteses executáveis, teste bruto automático e trilha de gerações.
-- Holdout, ordens, custos e slippage continuam fora deste executor.

alter table lab_automatizado.runs
  drop constraint if exists runs_run_type_check;

alter table lab_automatizado.runs
  add constraint runs_run_type_check check (
    run_type in ('quality_benchmark', 'research', 'strategy_backtest', 'portfolio_evaluation')
  );

alter table lab_automatizado.hypotheses
  add column if not exists executable_contract_version text;

create table if not exists lab_automatizado.hypothesis_test_runs (
  id uuid primary key default gen_random_uuid(),
  hypothesis_id uuid not null references lab_automatizado.hypotheses(id) on delete cascade,
  run_id uuid not null unique references lab_automatizado.runs(id) on delete cascade,
  phase text not null check (phase in ('development', 'validation', 'probe', 'portfolio')),
  generation integer not null default 0 check (generation between 0 and 5),
  variant_budget integer not null default 500 check (variant_budget between 1 and 500),
  time_budget_seconds integer not null default 7200 check (time_budget_seconds between 60 and 7200),
  created_at timestamptz not null default now(),
  unique (hypothesis_id, phase, generation)
);

create index if not exists hypothesis_test_runs_hypothesis_idx
  on lab_automatizado.hypothesis_test_runs (hypothesis_id, created_at desc);

create index if not exists hypothesis_test_runs_run_idx
  on lab_automatizado.hypothesis_test_runs (run_id);

alter table lab_automatizado.hypothesis_test_runs enable row level security;
revoke all on lab_automatizado.hypothesis_test_runs from public, anon, authenticated;
grant select, insert, update, delete on lab_automatizado.hypothesis_test_runs to service_role;

comment on table lab_automatizado.hypothesis_test_runs is
  'Vincula cada geração determinística de uma hipótese ao run do control plane.';

-- Contrato executável conservador para as duas hipóteses já registradas antes do V2.
-- A regra é explícita e versionada; não é uma decisão silenciosa do worker.
update lab_automatizado.hypotheses
   set executable_contract_version = 'hermes_execution_v2',
       payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
         'contract_version', 'hermes_execution_v2',
         'execution_spec', jsonb_build_object(
           'version', 1,
           'feature', jsonb_build_object(
             'kind', 'absorption_extreme',
             'aggression_quantile', 0.95,
             'absorption_move_quantile', 0.25,
             'trade_types', jsonb_build_array('AggressorBuyer', 'AggressorSeller')
           ),
           'entry', jsonb_build_object(
             'timing', 'first_trade_after_signal_minute',
             'side', 'same_as_signed_aggression'
           ),
           'exit', jsonb_build_object(
             'stop_ticks', 20,
             'target_ticks', 40,
             'time_stop_minutes', 15,
             'break_even', jsonb_build_object('enabled', true, 'activate_ticks', 20, 'offset_ticks', 0),
             'trailing', jsonb_build_object('enabled', false, 'activate_ticks', 30, 'distance_ticks', 20, 'step_ticks', 5),
             'partial', jsonb_build_object('enabled', false, 'fraction', 0.5, 'target_ticks', 20),
             'session_close', true
           ),
           'position', jsonb_build_object(
             'contracts_by_asset', jsonb_build_object('WDOFUT', 10, 'WINFUT', 50),
             'one_open_position_per_strategy_asset', true
           ),
           'search_budget', jsonb_build_object('max_variants', 500, 'max_seconds', 7200, 'max_generations', 5),
           'pricing_policy', 'gross_only',
           'holdout_policy', '2025_plus_locked_except_preregistered_probe_months'
         ),
         'primary_metric', 'gross_pnl_per_contract_month',
         'costs_applied', false,
         'slippage_applied', false
       )
 where payload->'execution_spec' is null;

update lab_automatizado.hypotheses
   set executable_contract_version = coalesce(executable_contract_version, 'hermes_execution_v2')
 where payload->'execution_spec' is not null;

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
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_run_id uuid;
  v_config jsonb := coalesce(p_config, '{}'::jsonb);
begin
  if p_run_type not in ('quality_benchmark', 'research', 'strategy_backtest', 'portfolio_evaluation') then
    raise exception 'run_type_not_allowed';
  end if;

  insert into lab_automatizado.runs (run_key, run_type, dataset_manifest, config, requested_by)
  values (p_run_key, p_run_type, p_dataset_manifest, v_config, p_requested_by)
  on conflict (run_key) do update set run_key = excluded.run_key
  returning id into v_run_id;

  insert into lab_automatizado.commands (run_id, command_type, idempotency_key, payload, requested_by)
  values (
    v_run_id, 'start_run', p_run_key || ':start',
    jsonb_build_object('run_type', p_run_type, 'dataset_manifest', p_dataset_manifest, 'config', v_config),
    p_requested_by
  )
  on conflict (idempotency_key) do nothing;

  insert into lab_automatizado.events (run_id, event_type, message, payload)
  values (v_run_id, 'run_queued', 'Execução colocada na fila.',
          jsonb_build_object('run_key', p_run_key, 'run_type', p_run_type));
  return v_run_id;
end;
$$;

create or replace function public.lab_automatizado_review_hypothesis(
  p_hypothesis_id uuid,
  p_status text,
  p_review_notes text,
  p_reviewed_by text
)
returns lab_automatizado.hypotheses
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_hypothesis lab_automatizado.hypotheses;
  v_run_id uuid;
  v_run_key text;
  v_config jsonb;
  v_notes text := left(trim(coalesce(p_review_notes, '')), 2000);
begin
  if p_status not in ('under_review', 'approved_for_test', 'rejected', 'archived') then
    raise exception 'hypothesis_status_not_allowed';
  end if;

  update lab_automatizado.hypotheses
     set status = p_status,
         review_notes = nullif(v_notes, ''),
         reviewed_by = nullif(trim(coalesce(p_reviewed_by, '')), ''),
         reviewed_at = now(),
         updated_at = now()
   where id = p_hypothesis_id
     and status not in ('archived', 'rejected')
   returning * into v_hypothesis;

  if v_hypothesis.id is null then
    raise exception 'hypothesis_not_reviewable';
  end if;

  if v_notes <> '' then
    insert into lab_automatizado.hypothesis_messages (
      hypothesis_id, author_type, author_key, message_type, body, delivery_status
    ) values (
      v_hypothesis.id,
      'human',
      coalesce(nullif(trim(p_reviewed_by), ''), 'panel'),
      case when p_status = 'under_review' then 'counterargument' else 'decision' end,
      left(v_notes, 8000),
      case when p_status = 'under_review' then 'pending' else 'answered' end
    );
  end if;

  if p_status in ('approved_for_test', 'rejected', 'archived') then
    update lab_automatizado.hypothesis_messages
       set delivery_status = 'failed',
           error_message = 'review_closed_before_hermes_response'
     where hypothesis_id = v_hypothesis.id
       and author_type = 'human'
       and message_type in ('counterargument', 'question', 'clarification')
       and delivery_status in ('pending', 'claimed');
  end if;

  if p_status = 'approved_for_test' then
    if v_hypothesis.asset is null
       or v_hypothesis.executable_contract_version <> 'hermes_execution_v2'
       or jsonb_typeof(v_hypothesis.payload->'execution_spec') <> 'object' then
      raise exception 'hypothesis_not_executable';
    end if;

    v_run_key := v_hypothesis.hypothesis_key || ':g0:development';
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
      'generation', 0,
      'max_variants', 500,
      'max_seconds', 7200,
      'execution_spec', v_hypothesis.payload->'execution_spec',
      'pricing_policy', 'gross_only',
      'costs_applied', false,
      'slippage_applied', false,
      'holdout_accessed', false,
      'holdout_policy', '2025_plus_locked_except_preregistered_probe_months',
      'dataset_manifest', 'development-full-v1'
    );

    select id into v_run_id from lab_automatizado.runs where run_key = v_run_key;
    if v_run_id is null then
      insert into lab_automatizado.runs (run_key, run_type, dataset_manifest, config, requested_by)
      values (v_run_key, 'strategy_backtest', 'development-full-v1', v_config, p_reviewed_by)
      returning id into v_run_id;

      insert into lab_automatizado.commands (run_id, command_type, idempotency_key, payload, requested_by)
      values (
        v_run_id, 'start_run', v_run_key || ':start',
        jsonb_build_object('run_type', 'strategy_backtest', 'dataset_manifest', 'development-full-v1', 'config', v_config),
        p_reviewed_by
      );

      insert into lab_automatizado.events (run_id, event_type, message, payload)
      values (v_run_id, 'hypothesis_test_queued', 'Hipótese aprovada; teste bruto de desenvolvimento enfileirado.',
              jsonb_build_object('hypothesis_id', v_hypothesis.id, 'generation', 0, 'phase', 'development'));
    end if;

    insert into lab_automatizado.hypothesis_test_runs
      (hypothesis_id, run_id, phase, generation, variant_budget, time_budget_seconds)
    values (v_hypothesis.id, v_run_id, 'development', 0, 500, 7200)
    on conflict (hypothesis_id, phase, generation) do nothing;
  end if;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    v_hypothesis.agent_key, 'hypothesis_reviewed', 'Hipótese revisada no painel.',
    jsonb_build_object('hypothesis_id', v_hypothesis.id, 'hypothesis_key', v_hypothesis.hypothesis_key,
                       'status', p_status, 'reviewed_by', p_reviewed_by, 'run_id', v_run_id)
  );

  return v_hypothesis;
end;
$$;

revoke all on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_enqueue_run(text, text, text, jsonb, text) to service_role;
grant execute on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) to service_role;

insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
values ('hermes-supervisor', 'execution_contract_v2_enabled',
        'Contrato declarativo V2 habilitado; aprovação passa a enfileirar teste bruto de desenvolvimento.',
        jsonb_build_object('max_variants', 500, 'max_generations', 5, 'max_drawdown_per_contract', 5000,
                           'costs_applied', false, 'slippage_applied', false));
