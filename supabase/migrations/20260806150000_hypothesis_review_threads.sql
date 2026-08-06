-- Conversa auditável entre o usuário e o Hermes por hipótese.
-- O conteúdo é append-only; os campos de delivery controlam apenas a fila interna.

create table if not exists lab_automatizado.hypothesis_messages (
  id uuid primary key default gen_random_uuid(),
  hypothesis_id uuid not null references lab_automatizado.hypotheses(id) on delete cascade,
  parent_message_id uuid references lab_automatizado.hypothesis_messages(id) on delete set null,
  author_type text not null check (author_type in ('human', 'hermes', 'system')),
  author_key text not null check (length(trim(author_key)) between 1 and 200),
  message_type text not null check (message_type in (
    'counterargument', 'question', 'clarification', 'response',
    'revision_proposal', 'abandonment', 'decision', 'system'
  )),
  body text not null check (length(trim(body)) between 1 and 8000),
  payload jsonb not null default '{}'::jsonb,
  delivery_status text not null default 'pending' check (delivery_status in (
    'pending', 'claimed', 'answered', 'failed'
  )),
  claimed_at timestamptz,
  claimed_by text,
  answered_at timestamptz,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists hypothesis_messages_thread_idx
  on lab_automatizado.hypothesis_messages (hypothesis_id, created_at asc);

create index if not exists hypothesis_messages_inbox_idx
  on lab_automatizado.hypothesis_messages (delivery_status, created_at asc)
  where author_type = 'human' and message_type in ('counterargument', 'question', 'clarification');

alter table lab_automatizado.hypothesis_messages enable row level security;
revoke all on lab_automatizado.hypothesis_messages from public, anon, authenticated;
grant select, insert, update on lab_automatizado.hypothesis_messages to service_role;

comment on table lab_automatizado.hypothesis_messages is
  'Trilha append-only de conversa Hermes-humano; delivery_status serve apenas a fila interna.';

create or replace function public.lab_automatizado_list_hypothesis_messages(
  p_hypothesis_id uuid,
  p_limit integer default 200
)
returns setof lab_automatizado.hypothesis_messages
language sql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
  select *
    from lab_automatizado.hypothesis_messages
   where hypothesis_id = p_hypothesis_id
   order by created_at asc
   limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

create or replace function public.lab_automatizado_post_hypothesis_message(
  p_hypothesis_id uuid,
  p_author_key text,
  p_message_type text,
  p_body text,
  p_parent_message_id uuid default null
)
returns lab_automatizado.hypothesis_messages
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_hypothesis lab_automatizado.hypotheses;
  v_message lab_automatizado.hypothesis_messages;
  v_body text := trim(coalesce(p_body, ''));
begin
  if p_message_type not in ('counterargument', 'question', 'clarification') then
    raise exception 'human_message_type_not_allowed';
  end if;

  if length(v_body) < 1 or length(v_body) > 8000 then
    raise exception 'hypothesis_message_length_invalid';
  end if;

  if length(trim(coalesce(p_author_key, ''))) < 1 then
    raise exception 'message_author_required';
  end if;

  select * into v_hypothesis
    from lab_automatizado.hypotheses
   where id = p_hypothesis_id
   for update;

  if v_hypothesis.id is null then
    raise exception 'hypothesis_not_found';
  end if;

  if v_hypothesis.status in ('rejected', 'archived') then
    raise exception 'hypothesis_not_reviewable';
  end if;

  if p_parent_message_id is not null and not exists (
    select 1
      from lab_automatizado.hypothesis_messages
     where id = p_parent_message_id
       and hypothesis_id = p_hypothesis_id
  ) then
    raise exception 'parent_message_not_found';
  end if;

  insert into lab_automatizado.hypothesis_messages (
    hypothesis_id, parent_message_id, author_type, author_key,
    message_type, body, delivery_status
  ) values (
    p_hypothesis_id, p_parent_message_id, 'human',
    nullif(trim(coalesce(p_author_key, '')), ''), p_message_type,
    v_body, 'pending'
  ) returning * into v_message;

  update lab_automatizado.hypotheses
     set status = 'under_review',
         review_notes = left(v_body, 2000),
         reviewed_by = nullif(trim(coalesce(p_author_key, '')), ''),
         reviewed_at = now(),
         updated_at = now()
   where id = p_hypothesis_id;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    v_hypothesis.agent_key,
    'hypothesis_message_received',
    'Nova mensagem humana aguardando resposta do Hermes.',
    jsonb_build_object(
      'hypothesis_id', p_hypothesis_id,
      'message_id', v_message.id,
      'message_type', p_message_type,
      'author_key', p_author_key
    )
  );

  return v_message;
end;
$$;

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

  return jsonb_build_object(
    'message', to_jsonb(v_message),
    'thread', v_thread
  );
end;
$$;

create or replace function public.lab_automatizado_publish_hermes_message(
  p_hypothesis_id uuid,
  p_parent_message_id uuid,
  p_message_type text,
  p_body text,
  p_payload jsonb default '{}'::jsonb,
  p_agent_key text default 'hermes-supervisor'
)
returns lab_automatizado.hypothesis_messages
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_parent lab_automatizado.hypothesis_messages;
  v_message lab_automatizado.hypothesis_messages;
  v_body text := trim(coalesce(p_body, ''));
begin
  if p_message_type not in ('response', 'revision_proposal', 'abandonment') then
    raise exception 'hermes_message_type_not_allowed';
  end if;

  if length(v_body) < 1 or length(v_body) > 8000 then
    raise exception 'hypothesis_message_length_invalid';
  end if;

  select * into v_parent
    from lab_automatizado.hypothesis_messages
   where id = p_parent_message_id
     and hypothesis_id = p_hypothesis_id
     and author_type = 'human'
     and delivery_status = 'claimed'
     and claimed_by = p_agent_key
   for update;

  if v_parent.id is null then
    raise exception 'claimed_parent_message_not_found';
  end if;

  insert into lab_automatizado.hypothesis_messages (
    hypothesis_id, parent_message_id, author_type, author_key,
    message_type, body, payload, delivery_status, answered_at
  ) values (
    p_hypothesis_id, p_parent_message_id, 'hermes', p_agent_key,
    p_message_type, v_body, coalesce(p_payload, '{}'::jsonb), 'answered', now()
  ) returning * into v_message;

  update lab_automatizado.hypothesis_messages
     set delivery_status = 'answered', answered_at = now()
   where id = p_parent_message_id;

  insert into lab_automatizado.agent_events (agent_key, event_type, message, payload)
  values (
    p_agent_key,
    'hypothesis_message_answered',
    'Hermes respondeu a uma revisão humana.',
    jsonb_build_object(
      'hypothesis_id', p_hypothesis_id,
      'message_id', v_message.id,
      'parent_message_id', p_parent_message_id,
      'message_type', p_message_type
    )
  );

  return v_message;
end;
$$;

create or replace function public.lab_automatizado_fail_hypothesis_message(
  p_message_id uuid,
  p_agent_key text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
begin
  update lab_automatizado.hypothesis_messages
     set delivery_status = 'failed',
         error_message = left(nullif(trim(coalesce(p_error_message, '')), ''), 1000)
   where id = p_message_id
     and author_type = 'human'
     and delivery_status = 'claimed'
     and claimed_by = p_agent_key;

  if not found then
    raise exception 'claimed_message_not_found';
  end if;
end;
$$;

-- Mantém a nota legada para compatibilidade, mas agora também registra uma
-- decisão/objeção no histórico da conversa quando o painel envia uma nota.
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

revoke all on function public.lab_automatizado_list_hypothesis_messages(uuid, integer) from public, anon, authenticated;
revoke all on function public.lab_automatizado_post_hypothesis_message(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.lab_automatizado_claim_hypothesis_message(text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_publish_hermes_message(uuid, uuid, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_fail_hypothesis_message(uuid, text, text) from public, anon, authenticated;
revoke all on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) from public, anon, authenticated;

grant execute on function public.lab_automatizado_list_hypothesis_messages(uuid, integer) to service_role;
grant execute on function public.lab_automatizado_post_hypothesis_message(uuid, text, text, text, uuid) to service_role;
grant execute on function public.lab_automatizado_claim_hypothesis_message(text) to service_role;
grant execute on function public.lab_automatizado_publish_hermes_message(uuid, uuid, text, text, jsonb, text) to service_role;
grant execute on function public.lab_automatizado_fail_hypothesis_message(uuid, text, text) to service_role;
grant execute on function public.lab_automatizado_review_hypothesis(uuid, text, text, text) to service_role;
