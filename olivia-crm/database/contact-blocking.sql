-- Bloqueo manual reversible para Olivia.
-- Conserva historial y datos del contacto; no equivale a una baja de marketing.

create or replace function public.olivia_set_contact_block(
  p_id uuid,
  p_blocked boolean,
  p_expected_updated_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.contacts;
  cancelled integer := 0;
  buffered integer := 0;
begin
  select * into c from public.contacts where id = p_id for update;
  if not found then raise exception 'Contacto no encontrado'; end if;
  if p_expected_updated_at is distinct from c.updated_at then raise exception 'La ficha ha cambiado'; end if;

  if p_blocked then
    update public.contacts
    set manual_tags = array(select distinct t from unnest(coalesce(manual_tags, '{}'::text[]) || array['crm_blocked']) as t where t <> ''),
        preferences = jsonb_set(coalesce(preferences, '{}'::jsonb), '{automation_block}', jsonb_build_object('blocked', true, 'blocked_at', clock_timestamp(), 'source', 'crm'), true),
        updated_at = clock_timestamp()
    where id = p_id
    returning * into c;

    update public.conversations
    set handoff_status = 'human', updated_at = clock_timestamp()
    where contact_id = p_id and handoff_status <> 'human';

    update public.outbound_dispatches
    set status = 'cancelled', error_message = 'Contacto bloqueado desde CRM'
    where contact_id = p_id and status = 'pending';
    get diagnostics cancelled = row_count;

    update public.inbound_message_buffer
    set status = 'processed', processed_at = clock_timestamp(), last_error = 'Contacto bloqueado desde CRM'
    where contact_id = p_id and status in ('pending', 'claimed');
    get diagnostics buffered = row_count;
  else
    update public.contacts
    set manual_tags = array_remove(coalesce(manual_tags, '{}'::text[]), 'crm_blocked'),
        preferences = jsonb_set(coalesce(preferences, '{}'::jsonb), '{automation_block}', jsonb_build_object('blocked', false, 'unblocked_at', clock_timestamp(), 'source', 'crm'), true),
        updated_at = clock_timestamp()
    where id = p_id
    returning * into c;
  end if;

  insert into public.contact_events(contact_id, event_type, source, metadata)
  values (p_id, 'contact_automation_block_changed', 'crm', jsonb_build_object('blocked', p_blocked, 'cancelled_dispatches', cancelled, 'discarded_buffered_messages', buffered));

  return jsonb_build_object('contact', to_jsonb(c), 'blocked', p_blocked, 'cancelled_dispatches', cancelled, 'discarded_buffered_messages', buffered);
end;
$$;

create or replace function public.ingest_olivia_inbound(
  p_channel text,
  p_external_message_id text,
  p_external_thread_id text,
  p_phone text,
  p_body text,
  p_message_type text default 'text',
  p_media jsonb default '[]'::jsonb,
  p_source_payload jsonb default '{}'::jsonb
) returns table(contact_id uuid, conversation_id uuid, buffer_id uuid)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_contact_id uuid;
  v_conversation_id uuid;
  v_buffer_id uuid;
  v_blocked boolean := false;
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
begin
  select c.id, coalesce(c.manual_tags, '{}'::text[]) @> array['crm_blocked']
  into v_contact_id, v_blocked
  from public.contacts c
  where regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g') = v_phone
  order by c.updated_at desc limit 1;

  if v_contact_id is null then
    insert into public.contacts(phone, stage, source, preferences)
    values (nullif(p_phone, ''), 'new', p_channel, '{}'::jsonb)
    returning id into v_contact_id;
  end if;

  select c.id into v_conversation_id from public.conversations c
  where c.contact_id = v_contact_id and c.channel = p_channel and c.status = 'open'
  order by c.updated_at desc limit 1;
  if v_conversation_id is null then
    insert into public.conversations(contact_id, channel, status, priority, handoff_status)
    values (v_contact_id, p_channel, 'open', 'normal', case when v_blocked then 'human' else 'bot' end)
    returning id into v_conversation_id;
  else
    update public.conversations set updated_at = now() where id = v_conversation_id;
  end if;

  insert into public.messages(conversation_id, direction, body, external_message_id)
  values (v_conversation_id, 'inbound', nullif(p_body, ''), p_external_message_id)
  on conflict (external_message_id) where external_message_id is not null do nothing;

  insert into public.inbound_message_buffer(channel, external_message_id, external_thread_id, contact_id, conversation_id, message_type, normalized_text, media, source_payload)
  values (p_channel, p_external_message_id, p_external_thread_id, v_contact_id, v_conversation_id, coalesce(p_message_type, 'text'), nullif(p_body, ''), coalesce(p_media, '[]'::jsonb), coalesce(p_source_payload, '{}'::jsonb))
  on conflict (channel, external_message_id) do update set source_payload = excluded.source_payload
  returning id into v_buffer_id;

  if v_blocked then
    update public.inbound_message_buffer
    set status = 'processed', processed_at = clock_timestamp(), last_error = 'Contacto bloqueado desde CRM'
    where id = v_buffer_id and status in ('pending', 'claimed');
  end if;
  return query select v_contact_id, v_conversation_id, v_buffer_id;
end;
$$;

create or replace function public.claim_inbound_message_batch(p_channel text, p_external_thread_id text, p_limit integer default 25)
returns setof public.inbound_message_buffer
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with ready as (
    select b.id from public.inbound_message_buffer b
    join public.contacts c on c.id = b.contact_id
    where b.channel = p_channel and coalesce(b.external_thread_id, '') = coalesce(p_external_thread_id, '')
      and b.status = 'pending'
      and not (coalesce(c.manual_tags, '{}'::text[]) @> array['crm_blocked'])
      and not exists(select 1 from public.inbound_message_buffer newer where newer.channel = p_channel
        and coalesce(newer.external_thread_id, '') = coalesce(p_external_thread_id, '')
        and newer.status = 'pending' and newer.process_after > now())
    order by b.received_at, b.id limit greatest(1, least(p_limit, 100)) for update skip locked
  )
  update public.inbound_message_buffer b set status = 'claimed', claimed_at = now(), attempts = b.attempts + 1
  from ready where b.id = ready.id returning b.*;
end;
$$;

create or replace function public.olivia_claim_customer_dispatch(p_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare d public.outbound_dispatches;c public.contacts;v public.conversations;cfg jsonb;acfg jsonb;permission text;is_notice boolean;in_window boolean;dtype text;tid text;lang text;components jsonb;
begin
 select value into cfg from public.olivia_config where key='bf2026';
 if not coalesce((cfg->>'whatsapp_outbound_enabled')::boolean,false) then return null; end if;
 select * into d from public.outbound_dispatches where id=p_id and status='pending' and channel='whatsapp' and coalesce(scheduled_for,created_at)<=now() for update skip locked;
 if not found or d.payload->>'kind'='human_handoff_alert' then return null; end if;
 if d.payload->>'kind'='early_access_welcome' and exists (select 1 from public.messages m join public.conversations cv on cv.id=m.conversation_id where cv.contact_id=d.contact_id and cv.channel='whatsapp' and m.direction='inbound') then
  update public.outbound_dispatches set status='cancelled',error_message='Bienvenida omitida: el contacto ya escribió por WhatsApp' where id=d.id;return null;
 end if;
 select * into c from public.contacts where id=d.contact_id;
 select * into v from public.conversations where id=d.conversation_id and contact_id=c.id;
 if coalesce(c.manual_tags, '{}'::text[]) @> array['crm_blocked'] then
  update public.outbound_dispatches set status='cancelled',error_message='Contacto bloqueado desde CRM' where id=d.id;return null;
 end if;
 if c.phone is null or v.id is null or nullif(cfg->>'whatsapp_phone_number_id','') is null then return null; end if;
 if d.payload->>'ai_disclosure_dispatch_id' is not null and not exists(select 1 from public.outbound_dispatches dep where dep.id::text=d.payload->>'ai_disclosure_dispatch_id' and dep.status in ('sent','delivered') and nullif(dep.external_dispatch_id,'') is not null and dep.error_message is null) then return null; end if;
 select status into permission from public.contact_channel_consents where contact_id=c.id and channel='whatsapp';
 if (permission='revoked' and not coalesce((d.payload->>'optout_confirmation')::boolean,false)) or (v.handoff_status in ('human','pending_human') and d.payload->>'sender_role' is distinct from 'human' and not coalesce((v.handoff_status='pending_human' and (d.payload->>'kind'='handoff_acknowledgement' or (d.payload->>'kind'='ai_disclosure' and exists(select 1 from public.outbound_dispatches ack where ack.id::text=d.payload->>'initial_response_id' and ack.payload->>'kind'='handoff_acknowledgement' and ack.status='pending')))),false)) then
  update public.outbound_dispatches set status='cancelled',error_message='Baja o control humano' where id=d.id;return null;
 end if;
 is_notice:=coalesce(d.payload->>'kind','')='ai_disclosure';
 if public.olivia_dispatch_needs_ai_notice(to_jsonb(d)) and not c.ai_disclosure_shown then return null; end if;
 select exists(select 1 from public.messages where conversation_id=v.id and direction='inbound' and created_at>now()-interval '23 hours 50 minutes') into in_window;
 dtype:=d.delivery_type;
 if is_notice then
  if c.ai_disclosure_shown then update public.outbound_dispatches set status='cancelled',error_message='Aviso IA ya confirmado' where id=d.id;return null; end if;
  if in_window then dtype:='freeform';
  else
   select value into acfg from public.olivia_config where key='ai_disclosure';
   if permission is distinct from 'granted' or not coalesce((acfg->>'template_approved')::boolean,false) or nullif(acfg->>'template_name','') is null then return null; end if;
   dtype:='template';tid:=acfg->>'template_name';lang:=coalesce(acfg->>'template_language','es');components:='[]';
  end if;
 elsif dtype in ('freeform','lead_magnet','checkout_link') and not in_window then
  update public.outbound_dispatches set status='cancelled',error_message='Ventana de respuesta cerrada' where id=d.id;return null;
 elsif dtype='template' then
  tid:=coalesce(nullif(d.payload->>'template_name',''),cfg->>'whatsapp_template_name');
  if permission is distinct from 'granted' or tid is null then return null; end if;
  if not ((tid=cfg->>'whatsapp_template_name' and coalesce((cfg->>'whatsapp_template_approved')::boolean,false)) or exists(select 1 from public.olivia_config t where t.key='outbound_templates' and coalesce((t.value#>>array[tid,'approved'])::boolean,false))) then return null; end if;
  lang:=coalesce(nullif(d.payload->>'template_language',''),cfg->>'whatsapp_template_language','es');components:=coalesce(d.payload->'template_components',cfg->'whatsapp_template_components','[]');
 end if;
 update public.outbound_dispatches set status='processing',delivery_type=dtype,claimed_at=now(),attempts=attempts+1,last_attempt_at=now() where id=d.id;
 return jsonb_build_object('dispatch_id',d.id,'kind',d.payload->>'kind','phone',c.phone,'delivery_type',dtype,'body',coalesce(d.payload->>'body',(select body from public.messages where id=d.message_id)),'image_url',d.payload->>'image_url','caption',d.payload->>'caption','sender_role',d.payload->>'sender_role','attempts',d.attempts+1,'template_name',coalesce(tid,cfg->>'whatsapp_template_name'),'template_language',coalesce(lang,cfg->>'whatsapp_template_language'),'template_components',coalesce(components,cfg->'whatsapp_template_components','[]'),'phone_number_id',cfg->>'whatsapp_phone_number_id');
end;
$$;

revoke all on function public.olivia_set_contact_block(uuid, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.olivia_set_contact_block(uuid, boolean, timestamptz) to service_role;
