-- Preserve the existing Hermes human-review thread while keeping the executable
-- strategy contract complete for the deterministic worker.

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

    select id into v_run_id
      from lab_automatizado.runs
     where run_key = v_run_key;

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
      values (
        v_run_id,
        'hypothesis_test_queued',
        'Hipótese aprovada; teste bruto de desenvolvimento enfileirado.',
        jsonb_build_object('hypothesis_id', v_hypothesis.id, 'generation', 0, 'phase', 'development')
      );
    end if;

    insert into lab_automatizado.hypothesis_test_runs
      (hypothesis_id, run_id, phase, generation, variant_budget, time_budget_seconds)
    values (v_hypothesis.id, v_run_id, 'development', 0, 500, 7200)
    on conflict (hypothesis_id, phase, generation) do nothing;
  end if;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    v_hypothesis.agent_key,
    'hypothesis_reviewed',
    'Hipótese revisada no painel.',
    jsonb_build_object(
      'hypothesis_id', v_hypothesis.id,
      'hypothesis_key', v_hypothesis.hypothesis_key,
      'status', p_status,
      'reviewed_by', p_reviewed_by,
      'run_id', v_run_id,
      'has_review_note', v_notes <> ''
    )
  );

  return v_hypothesis;
end;
$$;

revoke all on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) to service_role;
