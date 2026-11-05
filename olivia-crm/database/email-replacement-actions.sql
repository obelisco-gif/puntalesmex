CREATE OR REPLACE FUNCTION public.olivia_conversation_actions_b64(p_payload_b64 text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb; d jsonb:=p->'decision'; c public.contacts; cfg jsonb;
 batch uuid[]:=array(select jsonb_array_elements_text(coalesce(p->'batch_ids','[]'))::uuid);
 msg text; key_value text; result jsonb:='{}'; previous jsonb; prior_question text; registered boolean:=false; em text; email_changed boolean:=false; explicit_change boolean:=false; evidence text; entry jsonb; product uuid; ref text; phase text;
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
  explicit_change:=position(em in lower(msg))>0 and msg ~* '(cambia|cambiar|corrige|corregir|mejor.*(suscrib|apunt|email|correo|mail)|otro (email|correo|mail)|nuevo (email|correo|mail)|en (vez|lugar) de)';
  if (c.email is not null and lower(c.email)<>em and not explicit_change) or exists(select 1 from public.contacts where lower(email)=em and id<>c.id) then
   result:=result||jsonb_build_object('email_conflict',true);
  else
   email_changed:=c.email is not null and lower(c.email)<>em;
   if email_changed then
    insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key)
    values(c.id,'email_changed','conversation',jsonb_build_object('previous_email',c.email,'new_email',em,'request',left(msg,1000),'conversation_id',p->>'conversation_id'),key_value||':email-change');
    insert into public.contact_channel_consents(contact_id,channel,status,source,evidence)
    values(c.id,'email','unknown','conversation',jsonb_build_object('email',em,'request',left(msg,1000)))
    on conflict(contact_id,channel) do update set status='unknown',recorded_at=clock_timestamp(),source='conversation',evidence=excluded.evidence;
   end if;
   update public.contacts set email=em,updated_at=clock_timestamp() where id=c.id;
   if email_changed then result:=result||jsonb_build_object('email_changed',true);end if;
   result:=result||jsonb_build_object('email_saved',true);
   if coalesce((d->>'email_opt_in')::boolean,false) and (prior_question ~* '(email|correo|mail)' or msg ~* '(av[íi]s|recibir|env[íi]|mand|suscrib|ap[úu]nt).*(email|correo|mail)') then
    insert into public.contact_channel_consents(contact_id,channel,status,source,evidence)
    values(c.id,'email','granted','conversation',jsonb_build_object('email',em,'request',left(msg,1000),'offer',prior_question,'purpose','bf2026_early_access'))
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
 elsif result ? 'email_opt_in_recorded' then d:=d||jsonb_build_object('response_brief','Confirma que has guardado el email y su permiso y estás tramitando el alta de avisos por email. No confirmes pertenencia a Klaviyo ni envío hasta que conste confirmado.','pending_question',''); end if;
 perform public.olivia_store_lead_state(c.id,d);
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key) values(c.id,'conversation_actions','olivia',result||jsonb_build_object('decision',d),key_value);
 return encode(convert_to((p||jsonb_build_object('decision',d))::text,'utf8'),'base64');
end;$function$;
revoke all on function public.olivia_conversation_actions_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_conversation_actions_b64(text) to service_role;
