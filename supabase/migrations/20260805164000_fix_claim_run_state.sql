-- Ao reivindicar um comando, atualiza também o estado da execução.
create or replace function lab_automatizado.claim_next_command(p_worker_id text)
returns table (
  command_id uuid,
  run_id uuid,
  command_type text,
  payload jsonb,
  idempotency_key text
)
language plpgsql
security definer
set search_path = lab_automatizado, pg_catalog
as $$
begin
  return query
  with next_command as (
    select c.id
    from lab_automatizado.commands c
    where c.status = 'queued'
    order by c.requested_at, c.id
    for update skip locked
    limit 1
  ), claimed as (
    update lab_automatizado.commands c
       set status = 'claimed',
           claimed_by = p_worker_id,
           claimed_at = now()
      from next_command n
     where c.id = n.id
     returning c.id, c.run_id, c.command_type, c.payload, c.idempotency_key
  ), updated_runs as (
    update lab_automatizado.runs r
       set status = 'claimed',
           worker_id = p_worker_id,
           heartbeat_at = now(),
           updated_at = now()
      from claimed c
     where r.id = c.run_id
     returning r.id
  )
  select c.id, c.run_id, c.command_type, c.payload, c.idempotency_key
    from claimed c
    join updated_runs u on u.id = c.run_id;

  update lab_automatizado.workers
     set status = 'busy',
         last_heartbeat_at = now(),
         updated_at = now()
   where worker_id = p_worker_id;
end;
$$;

revoke all on function lab_automatizado.claim_next_command(text) from public, anon, authenticated;
grant execute on function lab_automatizado.claim_next_command(text) to service_role;
