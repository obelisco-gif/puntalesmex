alter table public.outbound_dispatches add column if not exists provider_attempt_at timestamptz;

create or replace function public.olivia_dispatcher_claim(p_id uuid default null) returns jsonb language plpgsql set search_path='' as $$
declare d public.outbound_dispatches; chosen uuid; outgoing jsonb;
begin
 if p_id is not null then
  select * into d from public.outbound_dispatches where id=p_id;
  chosen:=p_id;
  if d.payload->>'ai_disclosure_dispatch_id' is not null then
   select id into chosen from public.outbound_dispatches where id::text=d.payload->>'ai_disclosure_dispatch_id' and status='pending';
   chosen:=coalesce(chosen,p_id);
  end if;
  if d.payload->>'kind' is distinct from 'human_handoff_alert' then return public.olivia_claim_customer_dispatch(chosen); end if;
 end if;
 select x into outgoing from public.olivia_claim_outbound_v2(1) x limit 1;
 return outgoing;
end;$$;

create or replace function public.olivia_dispatcher_start(p_command jsonb) returns jsonb language plpgsql set search_path='' as $$
declare did uuid:=(p_command->>'dispatch_id')::uuid;
begin
 update public.outbound_dispatches set provider_attempt_at=clock_timestamp() where id=did and status='processing' and provider_attempt_at is null;
 if not found then return null; end if;
 return p_command;
end;$$;

create or replace function public.olivia_dispatcher_recover() returns jsonb language plpgsql set search_path='' as $$
declare safe_count integer;unknown_count integer;
begin
 update public.outbound_dispatches set status='pending',claimed_at=null,error_message='Reserva caducada antes de iniciar envío; recuperada'
 where status='processing' and claimed_at<now()-interval '10 minutes' and provider_attempt_at is null and payload->>'prompt_version'='bf26-v2';
 get diagnostics safe_count=row_count;
 update public.outbound_dispatches set status='failed',error_message='Resultado de envío desconocido tras interrupción; revisar antes de reintentar'
 where status='processing' and claimed_at<now()-interval '10 minutes' and provider_attempt_at is not null and payload->>'prompt_version'='bf26-v2';
 get diagnostics unknown_count=row_count;
 return jsonb_build_object('recovered',safe_count,'review_required',unknown_count);
end;$$;

create or replace function public.olivia_dispatcher_finish(p_result jsonb) returns jsonb language plpgsql set search_path='' as $$
declare d public.outbound_dispatches;ext text:=nullif(p_result->>'external_id','');err text:=left(coalesce(p_result->>'error','Sin confirmación del proveedor'),1500);retry boolean:=coalesce((p_result->>'retry_safe')::boolean,false);initial_id text;
begin
 select * into d from public.outbound_dispatches where id=(p_result->>'dispatch_id')::uuid and status='processing' for update;
 if not found then return jsonb_build_object('processed_count',20); end if;
 if ext is not null then perform public.complete_olivia_outbound(d.id,ext,null);
 elsif retry and d.attempts<3 then
  update public.outbound_dispatches set status='pending',provider_attempt_at=null,claimed_at=null,error_message=err,scheduled_for=now()+make_interval(secs=>30*power(2,d.attempts)::integer) where id=d.id;
 else perform public.complete_olivia_outbound(d.id,null,err); end if;
 if ext is not null and d.payload->>'kind'='ai_disclosure' then initial_id:=d.payload->>'initial_response_id'; end if;
 return jsonb_build_object('processed_count',coalesce((p_result->>'processed_count')::integer,0)+1,'dispatch_id',initial_id);
end;$$;
revoke all on function public.olivia_dispatcher_claim(uuid),public.olivia_dispatcher_start(jsonb),public.olivia_dispatcher_recover(),public.olivia_dispatcher_finish(jsonb) from public,anon,authenticated;
grant execute on function public.olivia_dispatcher_claim(uuid),public.olivia_dispatcher_start(jsonb),public.olivia_dispatcher_recover(),public.olivia_dispatcher_finish(jsonb) to service_role;
