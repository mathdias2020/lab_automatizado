create or replace function public.lab_automatizado_requeue_hypothesis_message(
  p_message_id uuid,
  p_agent_key text,
  p_reason text default 'review delivery recovery'
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $function$
begin
  update lab_automatizado.hypothesis_messages as hm
     set delivery_status = 'pending',
         claimed_at = null,
         claimed_by = null,
         error_message = left(nullif(trim(coalesce(p_reason, '')), ''), 1000)
   where hm.id = p_message_id
     and hm.author_type = 'human'
     and hm.delivery_status = 'claimed'
     and hm.claimed_by = p_agent_key
     and not exists (
       select 1
         from lab_automatizado.hypothesis_messages as child
        where child.parent_message_id = hm.id
          and child.author_type = 'hermes'
     );

  return found;
end;
$function$;

revoke all on function public.lab_automatizado_requeue_hypothesis_message(uuid, text, text) from public;
grant execute on function public.lab_automatizado_requeue_hypothesis_message(uuid, text, text) to service_role;
