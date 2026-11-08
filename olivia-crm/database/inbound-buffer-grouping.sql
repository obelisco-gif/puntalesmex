create or replace function public.claim_inbound_message_batch(p_channel text,p_external_thread_id text,p_limit integer default 25)
returns setof public.inbound_message_buffer language plpgsql security definer set search_path='' as $fn$
begin
 return query
 with ready as (
  select b.id from public.inbound_message_buffer b
  where b.channel=p_channel and coalesce(b.external_thread_id,'')=coalesce(p_external_thread_id,'')
   and b.status='pending'
   and not exists(select 1 from public.inbound_message_buffer newer where newer.channel=p_channel
    and coalesce(newer.external_thread_id,'')=coalesce(p_external_thread_id,'')
    and newer.status='pending' and newer.process_after>now())
  order by b.received_at,b.id limit greatest(1,least(p_limit,100)) for update skip locked
 )
 update public.inbound_message_buffer b set status='claimed',claimed_at=now(),attempts=b.attempts+1
 from ready where b.id=ready.id returning b.*;
end;$fn$;
