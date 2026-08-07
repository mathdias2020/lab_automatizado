create or replace function public.lab_automatizado_record_lab_cycle(p_error text default null)
returns lab_automatizado.lab_control
language plpgsql
security definer
set search_path = pg_catalog, public, lab_automatizado
as $$
declare
  v_control lab_automatizado.lab_control;
begin
  update lab_automatizado.lab_control
     set last_cycle_at = now(),
         last_error = nullif(left(trim(coalesce(p_error, '')), 1000), ''),
         updated_at = now()
   where id = true
   returning * into v_control;
  return v_control;
end;
$$;

revoke all on function public.lab_automatizado_record_lab_cycle(text) from public, anon, authenticated;
grant execute on function public.lab_automatizado_record_lab_cycle(text) to service_role;
