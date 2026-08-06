-- Não deixa o Hermes responder a uma thread encerrada por decisão humana.

create or replace function public.lab_automatizado_claim_hypothesis_message(
  p_agent_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_message lab_automatizado.hypothesis_messages;
  v_thread jsonb;
begin
  if not exists (
    select 1 from lab_automatizado.agents where agent_key = p_agent_key and agent_type = 'hermes'
  ) then
    raise exception 'agent_not_registered';
  end if;

  update lab_automatizado.hypothesis_messages as hm
     set delivery_status = 'claimed',
         claimed_at = now(),
         claimed_by = p_agent_key,
         error_message = null
   where hm.id = (
     select candidate.id
       from lab_automatizado.hypothesis_messages as candidate
      where candidate.author_type = 'human'
        and candidate.message_type in ('counterargument', 'question', 'clarification')
        and (
          candidate.delivery_status = 'pending'
          or (candidate.delivery_status = 'claimed' and candidate.claimed_at < now() - interval '30 minutes')
        )
        and exists (
          select 1
            from lab_automatizado.hypotheses as h
           where h.id = candidate.hypothesis_id
             and h.status in ('proposed', 'under_review')
        )
      order by candidate.created_at asc
      for update skip locked
      limit 1
   )
   returning hm.* into v_message;

  if v_message.id is null then
    return null;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(thread_row) order by thread_row.created_at asc),
    '[]'::jsonb
  ) into v_thread
    from (
      select *
        from lab_automatizado.hypothesis_messages
       where hypothesis_id = v_message.hypothesis_id
       order by created_at asc
       limit 200
    ) as thread_row;

  return jsonb_build_object('message', to_jsonb(v_message), 'thread', v_thread);
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
  v_notes text := trim(coalesce(p_review_notes, ''));
begin
  if p_status not in ('under_review', 'approved_for_test', 'rejected', 'archived') then
    raise exception 'hypothesis_status_not_allowed';
  end if;

  update lab_automatizado.hypotheses
     set status = p_status,
         review_notes = nullif(left(v_notes, 2000), ''),
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
      'has_review_note', v_notes <> ''
    )
  );

  return v_hypothesis;
end;
$$;

revoke all on function public.lab_automatizado_claim_hypothesis_message(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_claim_hypothesis_message(text) to service_role;
grant execute on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) to service_role;
