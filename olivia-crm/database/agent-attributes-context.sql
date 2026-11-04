CREATE OR REPLACE FUNCTION public.olivia_contact_score(p_contact uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.contacts; points int; reasons jsonb:='[]'; override_value int; semantic_score int; semantic_reason text;
begin
 select * into c from public.contacts where id=p_contact;
 points:=case c.stage when 'engaged' then 15 when 'qualified' then 35 when 'recommended' then 45 when 'purchase_intent' then 65 when 'customer' then 70 else 0 end;
 reasons:=jsonb_build_array(jsonb_build_object('reason','Fase comercial','points',points));
 if 'bf2026_early_access'=any(c.manual_tags) then points:=points+15; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Early Access','points',15)); end if;
 if exists(select 1 from public.contact_commercial_entries where contact_id=c.id and kind='interest' and product_id is not null and status<>'cancelled') then points:=points+10; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Interés declarado en producto','points',10)); end if;
 if exists(select 1 from public.contact_commercial_entries where contact_id=c.id and kind='purchase' and status='confirmed') then points:=points+20; reasons:=reasons||jsonb_build_array(jsonb_build_object('reason','Compra confirmada en CRM','points',20)); end if;
 select lead_score,score_reason into semantic_score,semantic_reason from public.lead_states where contact_id=c.id;
 if semantic_score is not null then points:=semantic_score; reasons:=jsonb_build_array(jsonb_build_object('reason',coalesce(nullif(semantic_reason,''),'Valoración del agente'),'points',semantic_score)); end if;
 if c.stage='customer' and exists(select 1 from public.contact_commercial_entries where contact_id=c.id and kind='purchase' and status='confirmed') then points:=greatest(points,85); end if;
 if c.stage in ('lost','unsubscribed') then points:=0; end if;
 override_value:=(c.preferences#>>'{commercial,score_override}')::int;
 return jsonb_build_object('value',coalesce(override_value,least(100,points)),'automatic',least(100,points),'manual',override_value is not null,'reasons',reasons);
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_context_v2_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; result jsonb;
begin
 select jsonb_build_object(
 'contact_id',c.id,'conversation_id',v.id,'batch_text',p->>'batch_text','batch_ids',coalesce(p->'batch_ids','[]'::jsonb),
 'contact',jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'source',c.source,'tags',c.manual_tags,'preferences',c.preferences,'attributes',public.olivia_get_attributes(c.id)),
 'attributes',public.olivia_get_attributes(c.id),
 'attribute_records',coalesce((select jsonb_agg(to_jsonb(a) order by attribute_key) from public.lead_attributes a where contact_id=c.id and status='confirmed'),'[]'),
 'tool_results',coalesce((select jsonb_agg(metadata) from public.contact_events where contact_id=c.id and event_type='agent_tool' and metadata->'batch_ids' @> coalesce(p->'batch_ids','[]') and metadata->'batch_ids' <@ coalesce(p->'batch_ids','[]')),'[]'),
 'commercial_profile',public.olivia_commercial_profile(c.id),
 'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from (select * from public.contact_commercial_entries where contact_id=c.id order by updated_at desc limit 50)e),'[]'::jsonb),
 'score',public.olivia_contact_score(c.id),
 'lead_state',coalesce(c.preferences->'olivia','{}'::jsonb)||coalesce((select to_jsonb(ls)-'contact_id' from public.lead_states ls where ls.contact_id=c.id),'{}'),
 'conversation',jsonb_build_object('status',v.status,'handoff_status',v.handoff_status),
 'channel_consents',coalesce((select jsonb_object_agg(channel,jsonb_build_object('status',status,'recorded_at',recorded_at)) from public.contact_channel_consents where contact_id=c.id),'{}'::jsonb),
 'campaign',(select value from public.olivia_config where key='bf2026'),
 'early_access_registered','bf2026_early_access'=any(c.manual_tags),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by created_at) from (select direction,body,created_at from public.messages where conversation_id=v.id order by created_at desc limit 20)h),'[]'::jsonb),
 'document_index',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'packages',d.routing_packages,'product_ids',public.olivia_document_product_ids(d.id,d.catalog_product_id))) from public.product_documents d where d.approval_status='approved' and not d.routing_packages && array['internal_ops']),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'stock_status',stock_status,'price',price,'synced_at',synced_at)) from public.catalog_products where status='publish'),'[]'::jsonb),
 'now',now()) into result
 from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id=(p->>'contact_id')::uuid and v.id=(p->>'conversation_id')::uuid;
 return coalesce(result,'{}'::jsonb);
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_conversation_actions_b64(p_payload_b64 text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; d jsonb:=p->'decision'; c public.contacts; cfg jsonb;
 batch uuid[]:=array(select jsonb_array_elements_text(coalesce(p->'batch_ids','[]'))::uuid);
 msg text; key_value text; result jsonb:='{}'; previous jsonb; prior_question text; registered boolean:=false; em text; evidence text; entry jsonb; product uuid; ref text; phase text;
begin
 select * into c from public.contacts where id=(p->>'contact_id')::uuid for update;
 if not found or not exists(select 1 from public.conversations where id=(p->>'conversation_id')::uuid and contact_id=c.id) then raise exception 'Contact/conversation mismatch'; end if;
 if cardinality(batch)=0 or (select count(*) from public.inbound_message_buffer where id=any(batch) and contact_id=c.id and conversation_id=(p->>'conversation_id')::uuid and status='claimed')<>cardinality(batch) then raise exception 'Claimed batch required'; end if;
 -- Use the received text from storage, never trust model-supplied evidence alone.
 select string_agg(normalized_text,E'\n' order by received_at,id) into msg from public.inbound_message_buffer where id=any(batch);
 key_value:='conversation-actions:'||md5(array_to_string(array(select unnest(batch) order by 1),','));
 select metadata into previous from public.contact_events where idempotency_key=key_value;
 if previous is not null then d:=coalesce(previous->'decision',d||jsonb_build_object('action_result',previous)); return encode(convert_to((p||jsonb_build_object('decision',d))::text,'utf8'),'base64'); end if;
 if coalesce((d->>'opt_out')::boolean,false)
 or exists(select 1 from public.conversations where id=(p->>'conversation_id')::uuid and handoff_status in ('human','pending_human'))
 or exists(select 1 from public.contact_channel_consents where contact_id=c.id and channel='whatsapp' and status='revoked') then
  return p_payload_b64;
 end if;
 select exists(select 1 from public.contact_events where contact_id=c.id and event_type='agent_tool'
 and metadata->>'operation'='save_tags' and (metadata->'batch_ids') @> (p->'batch_ids') and (metadata->'batch_ids') <@ (p->'batch_ids') and metadata#>>'{result,registered}'='true') into registered;
 if registered then result:=jsonb_build_object('registered',true,'welcome_by','olivia'); end if;
 prior_question:=coalesce(c.preferences#>>'{olivia,pending_question}','');
 select value into cfg from public.olivia_config where key='bf2026';
 evidence:=nullif(d->>'registration_evidence','');
 if d->>'early_access_action'='registration_requested' and not coalesce((d->>'needs_human')::boolean,false) and not ('bf2026_early_access'=any(c.manual_tags))
 and coalesce((cfg->>'registration_open')::boolean,false) and evidence is not null and position(lower(evidence) in lower(msg))>0
 and (lower(msg) ~ '(ap[úu]ntame|inscr[íi]beme|quiero (apuntarme|inscribirme|registrarme)|me quiero (apuntar|inscribir))'
 or (prior_question ~* '(apunt|inscrib).*(early access|acceso anticipado)' and lower(btrim(msg)) ~ '^(s[íi]|vale|ok|de acuerdo|claro|perfecto|adelante)([ ,.!]|$)')) then
  insert into public.contact_channel_consents(contact_id,channel,status,source,evidence)
  values(c.id,'whatsapp','granted','conversation',jsonb_build_object('request',left(msg,1000),'offer',prior_question,'purpose','bf2026_early_access'))
  on conflict(contact_id,channel) do update set status='granted',recorded_at=clock_timestamp(),source='conversation',evidence=excluded.evidence;
  -- Marker and tag in the same update: the trigger suppresses the template welcome.
  update public.contacts set preferences=jsonb_set(preferences,'{early_access}',jsonb_build_object('source','conversation','welcomed_by','olivia','registered_at',now())),
  manual_tags=array(select distinct unnest(manual_tags||array['bf2026_early_access'])),updated_at=clock_timestamp() where id=c.id;
  registered:=true;
  result:=result||jsonb_build_object('registered',true,'welcome_by','olivia','channel','whatsapp');
 end if;
 if d->>'early_access_action'='registration_requested' and not registered and not ('bf2026_early_access'=any(c.manual_tags)) then result:=result||jsonb_build_object('registration_not_completed',true); end if;
 em:=lower(nullif(btrim(d->>'captured_email'),''));
 if em is null and c.email is not null and coalesce((d->>'email_opt_in')::boolean,false)
 and (msg ~* '(av[íi]s|recibir|env[íi]|mand).*(email|correo)' or (prior_question ~* '(email|correo)' and lower(btrim(msg)) ~ '^(s[íi]|vale|ok|de acuerdo|claro|perfecto|adelante)([ ,.!]|$)')) then em:=lower(c.email); end if;
 if em is not null and em ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and (position(em in lower(msg))>0 or em=lower(c.email)) then
  perform pg_advisory_xact_lock(hashtextextended('olivia-email:'||em,0));
  if (c.email is not null and lower(c.email)<>em) or exists(select 1 from public.contacts where lower(email)=em and id<>c.id) then
   result:=result||jsonb_build_object('email_conflict',true);
  else
   update public.contacts set email=em,updated_at=clock_timestamp() where id=c.id;
   result:=result||jsonb_build_object('email_saved',true);
   if coalesce((d->>'email_opt_in')::boolean,false) and (prior_question ~* '(email|correo)' or msg ~* '(av[íi]s|recibir|env[íi]|mand).*(email|correo)') then
    insert into public.contact_channel_consents(contact_id,channel,status,source,evidence)
    values(c.id,'email','granted','conversation',jsonb_build_object('request',left(msg,1000),'offer',prior_question,'purpose','bf2026_early_access'))
    on conflict(contact_id,channel) do update set status='granted',recorded_at=clock_timestamp(),source='conversation',evidence=excluded.evidence;
    result:=result||jsonb_build_object('email_opt_in_recorded',true);
   end if;
  end if;
 end if;
 -- Explicit product/order facts only. The model cannot create confirmed purchases.
 if not exists(select 1 from public.contact_events where contact_id=c.id and event_type='agent_tool' and metadata->>'operation'='save_atributos' and (metadata->'batch_ids') @> (p->'batch_ids') and (metadata->'batch_ids') <@ (p->'batch_ids') and metadata#>>'{result,saved}'='true') then
 for entry in select value from jsonb_array_elements(coalesce(d->'commercial_updates','[]')) limit 5 loop
  if entry->>'kind' not in ('interest','avoid','order_inquiry') or nullif(entry->>'evidence','') is null or position(lower(entry->>'evidence') in lower(msg))=0 then continue; end if;
  product:=null;
  select id into product from public.catalog_products where id::text=entry->>'product_id' and status='publish';
  ref:=case when entry->>'kind' in ('interest','avoid') and product is not null then 'product:'||product::text else left(coalesce(entry->>'reference',''),120) end;
  if entry->>'kind'='order_inquiry' and ref<>'' and position(lower(ref) in lower(msg))=0 then ref:=''; end if;
  insert into public.contact_commercial_entries(contact_id,kind,product_id,reference,details,status,source,evidence)
  values(c.id,entry->>'kind',product,ref,left(coalesce(nullif(entry->>'details',''),entry->>'evidence'),2000),'open','conversation',left(entry->>'evidence',1000))
  on conflict(contact_id,kind,reference) where reference<>'' do update set details=excluded.details,evidence=excluded.evidence,updated_at=clock_timestamp();
 end loop;
 end if;
 phase:=d->>'suggested_stage';
 if c.stage not in ('customer','unsubscribed') and phase in ('engaged','qualified','recommended','purchase_intent','on_hold','lost') then
  update public.contacts set stage=phase,updated_at=clock_timestamp() where id=c.id;
 end if;
 d:=d||jsonb_build_object('action_result',result);
 if registered then
  d:=d||jsonb_build_object('early_access_action','already_registered','response_brief','Da tú la bienvenida a Early Access: el alta está confirmada. Acceso 24 horas antes del público, stock limitado, sin reserva. No redirijas a un formulario ni prometas stock o enlaces inexistentes.',
   'pending_question',case when coalesce(em,c.email) is null then '¿Quieres que también te avisemos por email? Si te interesa, dime tu correo.' else '' end);
 elsif result ? 'registration_not_completed' then
  d:=d||jsonb_build_object('pending_question','¿Quieres que te apunte al acceso anticipado y te avisemos por WhatsApp?', 'response_brief','No se ha completado ningún alta. Pide aceptación de forma natural, sin enlace externo.');
 end if;
 if result ? 'email_conflict' then d:=d||jsonb_build_object('response_brief','No se ha cambiado el email porque requiere revisión del equipo. No confirmes alta por email.','needs_human',true,'pending_question','');
 elsif result ? 'email_opt_in_recorded' then d:=d||jsonb_build_object('response_brief','Confirma que has guardado el email y su permiso para los avisos del acceso anticipado. No afirmes que se ha enviado ya ningún email.','pending_question',''); end if;
 perform public.olivia_store_lead_state(c.id,d);
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key) values(c.id,'conversation_actions','olivia',result||jsonb_build_object('decision',d),key_value);
 return encode(convert_to((p||jsonb_build_object('decision',d))::text,'utf8'),'base64');
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_complete_v2_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;
 d jsonb:=coalesce(p->'decision','{}'); cid uuid:=(p->>'contact_id')::uuid; vid uuid:=(p->>'conversation_id')::uuid;
 mid uuid; did uuid; batch uuid[]:=array(select jsonb_array_elements_text(coalesce(p->'batch_ids','[]'))::uuid);
 opt boolean:=coalesce((d->>'opt_out')::boolean,false); human boolean:=coalesce((d->>'needs_human')::boolean,false);
 scope text:=coalesce(d->>'opt_out_scope','whatsapp'); reply text:=left(coalesce(p->>'reply_text',''),1600);
 key text;
begin
 perform 1 from public.conversations where id=vid and contact_id=cid for update;
 if not found then raise exception 'Contact/conversation mismatch'; end if;
 if cardinality(batch)=0 then raise exception 'Inbound batch required'; end if;
 if exists(select 1 from public.inbound_message_buffer where id=any(batch) and (contact_id<>cid or conversation_id<>vid)) then raise exception 'Invalid batch ownership'; end if;
 if (select count(*) from public.inbound_message_buffer where id=any(batch) and status='claimed')<>cardinality(batch) then
  return jsonb_build_object('duplicate_or_unclaimed',true);
 end if;
 key:='olivia-reply:'||md5(array_to_string(array(select unnest(batch) order by 1),','));
 if opt then
  if scope not in ('whatsapp','email','all') then scope:='whatsapp'; end if;
  perform public.olivia_apply_optout(cid,scope,coalesce(p->>'batch_text',''));
  if scope='whatsapp' then reply:='He registrado tu baja de los mensajes de WhatsApp de Sadiet.';
  elsif scope='email' then reply:='He registrado tu solicitud de baja de los emails de Sadiet.';
  else reply:='He registrado tu solicitud de baja de las comunicaciones de Sadiet.'; end if;
 elsif human then
  update public.conversations set handoff_status='pending_human',priority='high',updated_at=now() where id=vid;
 elsif exists(select 1 from public.conversations where id=vid and handoff_status in ('human','pending_human')) then
  reply:='';
 end if;
 update public.contacts set preferences=jsonb_set(preferences,'{olivia}',
  coalesce(preferences->'olivia','{}')||jsonb_build_object('summary',left(coalesce(d->>'summary',''),3000),'last_intent',d->>'intent','pending_question',d->>'pending_question','early_access_action',d->>'early_access_action','temperature',d->>'temperature','updated_at',now())),updated_at=now() where id=cid;
 perform public.olivia_store_lead_state(cid,d);
 insert into public.agent_runs(conversation_id,contact_id,inbound_batch_ids,agent_role,status,decision,prompt_version,input_summary,output_summary,completed_at)
 values(vid,cid,batch,'conversation',case when reply='' then 'skipped' else 'completed' end,d,'bf26-v2',left(p->>'batch_text',2000),reply,now());
 if reply<>'' and (opt or not exists(select 1 from public.contact_channel_consents where contact_id=cid and channel='whatsapp' and status='revoked')) then
  insert into public.messages(conversation_id,direction,body) values(vid,'outbound',reply) returning id into mid;
  insert into public.outbound_dispatches(contact_id,conversation_id,message_id,channel,delivery_type,payload,idempotency_key)
  values(cid,vid,mid,'whatsapp','freeform',jsonb_build_object('body',reply,'optout_confirmation',opt,'prompt_version','bf26-v2'),key)
  on conflict(idempotency_key) where idempotency_key is not null do nothing returning id into did;
 end if;
 update public.inbound_message_buffer set status='processed',processed_at=now() where id=any(batch) and status='claimed';
 return jsonb_build_object('saved',true,'dispatch_id',did,'opt_out_recorded',opt,'needs_human',human);
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_dashboard_contacts()
 RETURNS SETOF jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select to_jsonb(c)||jsonb_build_object('attributes',public.olivia_get_attributes(c.id),'attribute_records',coalesce((select jsonb_agg(to_jsonb(a) order by attribute_key) from public.lead_attributes a where a.contact_id=c.id and status='confirmed'),'[]'),'preferences',jsonb_set(c.preferences,'{commercial}',public.olivia_commercial_profile(c.id)),'lead_state',(select to_jsonb(ls) from public.lead_states ls where ls.contact_id=c.id),'score',public.olivia_contact_score(c.id),'commercial_entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.updated_at desc) from public.contact_commercial_entries e where e.contact_id=c.id),'[]'::jsonb))
 from public.contacts c order by c.updated_at desc limit 100;
$function$;

CREATE OR REPLACE FUNCTION public.olivia_save_contact(p_id uuid, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.contacts; profile jsonb:=coalesce(p_input->'commercial','{}'); k text;
begin
 select * into c from public.contacts where id=p_id for update;
 if not found then raise exception 'Contacto no encontrado'; end if;
 if nullif(p_input->>'expected_updated_at','')::timestamptz is distinct from c.updated_at then raise exception 'El contacto ha cambiado. Actualiza la ficha antes de guardar.'; end if;
 for k in select jsonb_object_keys(profile) loop
  if k not in ('tastes','objections','buying_horizon','score_override') then raise exception 'Atributo no válido'; end if;
 end loop;
 if jsonb_typeof(profile)<>'object' or length(coalesce(profile->>'tastes',''))>2000 or length(coalesce(profile->>'objections',''))>2000 or length(coalesce(profile->>'buying_horizon',''))>500 then raise exception 'Atributos no válidos'; end if;
 if profile->>'score_override' is not null and (profile->>'score_override')::int not between 0 and 100 then raise exception 'Score entre 0 y 100'; end if;
 update public.contacts set first_name=case when p_input ? 'first_name' then nullif(btrim(left(p_input->>'first_name',100)),'') else first_name end,stage=coalesce(p_input->>'stage',stage),internal_notes=left(coalesce(p_input->>'internal_notes',internal_notes),10000),
 assigned_to=case when p_input ? 'assigned_to' then nullif(left(p_input->>'assigned_to',100),'') else assigned_to end,
 manual_tags=case when p_input ? 'manual_tags' then array(select distinct jsonb_array_elements_text(p_input->'manual_tags')) else manual_tags end,
 preferences=jsonb_set(preferences,'{commercial}',coalesce(preferences->'commercial','{}')||profile)||case when p_input ? 'first_name' then jsonb_build_object('name_source','crm') else '{}'::jsonb end,updated_at=clock_timestamp()
 where id=p_id returning * into c;
 update public.lead_states set phase=c.stage,updated_at=clock_timestamp() where contact_id=c.id;
 return to_jsonb(c);
end;$function$;




