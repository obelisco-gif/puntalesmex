-- Olivia: canonical attributes and persisted commercial state, modelled on Dina.
-- Single-tenant Sadiet; no changes to Dina's database or workflows.
create table public.lead_attributes (
 id uuid primary key default gen_random_uuid(),
 contact_id uuid not null references public.contacts(id) on delete cascade,
 namespace text not null default 'commercial' check(namespace='commercial'),
 attribute_key text not null check(attribute_key ~ '^[a-z][a-z0-9_]{1,60}$'),
 value_text text not null,
 value_jsonb jsonb not null check(value_jsonb<>'null'::jsonb),
 confidence numeric(3,2) not null default 0.9 check(confidence between 0 and 1),
 source text not null check(source in ('llm','crm','import')),
 status text not null default 'confirmed' check(status in ('confirmed','superseded')),
 evidence text,
 observed_at timestamptz not null default now(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(contact_id,namespace,attribute_key)
);
alter table public.lead_attributes enable row level security;
revoke all on public.lead_attributes from anon,authenticated;
grant all on public.lead_attributes to service_role;

create table public.lead_states (
 contact_id uuid primary key references public.contacts(id) on delete cascade,
 phase text not null,
 temperature text not null default 'cold' check(temperature in ('cold','warm','hot')),
 lead_score integer not null default 0 check(lead_score between 0 and 100),
 score_reason text not null default '',
 summary text not null default '',
 pending_question text not null default '',
 last_intent text,
 updated_at timestamptz not null default clock_timestamp()
);
alter table public.lead_states enable row level security;
revoke all on public.lead_states from anon,authenticated;
grant all on public.lead_states to service_role;

create function public.olivia_get_attributes(p_contact uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_object_agg(attribute_key,value_jsonb),'{}') from public.lead_attributes where contact_id=p_contact and status='confirmed';
$$;

create function public.olivia_record_attribute(p_contact uuid,p_key text,p_value jsonb,p_evidence text,p_source text,p_mode text default 'merge') returns jsonb language plpgsql security invoker set search_path='' as $$
declare old_row public.lead_attributes; final_value jsonb; result public.lead_attributes;
begin
 if p_key !~ '^[a-z][a-z0-9_]{1,60}$' or p_key in ('__proto__','constructor','prototype') then raise exception 'Clave de atributo no válida'; end if;
 if p_value is null or p_value='null'::jsonb or jsonb_typeof(p_value) not in ('string','number','boolean','array') or length(p_value::text)>4000 or p_value='""'::jsonb or p_value='[]'::jsonb then raise exception 'Valor de atributo no válido'; end if;
 if jsonb_typeof(p_value)='array' and (jsonb_array_length(p_value)>30 or exists(select 1 from jsonb_array_elements(p_value) x where jsonb_typeof(x)<>'string')) then raise exception 'La lista requiere textos'; end if;
 if p_source not in ('llm','crm','import') or p_mode not in ('merge','replace','remove') then raise exception 'Origen o modo no válido'; end if;
 perform 1 from public.contacts where id=p_contact for update;
 if not found then raise exception 'Contacto no encontrado'; end if;
 select * into old_row from public.lead_attributes where contact_id=p_contact and namespace='commercial' and attribute_key=p_key for update;
 if old_row.source='crm' and p_source<>'crm' then return jsonb_build_object('saved',false,'reason','manual_value_preserved','attribute_key',p_key); end if;
 final_value:=p_value;
 if jsonb_typeof(p_value)='array' and jsonb_typeof(old_row.value_jsonb)='array' and p_mode='merge' then
  select coalesce(jsonb_agg(value order by value),'[]') into final_value from (select distinct value from jsonb_array_elements(old_row.value_jsonb||p_value)) s;
 elsif p_mode='remove' then
  if jsonb_typeof(p_value)<>'array' then raise exception 'Retirar requiere una lista'; end if;
  select coalesce(jsonb_agg(value order by value),'[]') into final_value from jsonb_array_elements(case when jsonb_typeof(old_row.value_jsonb)='array' then old_row.value_jsonb else '[]'::jsonb end) x(value) where not p_value @> jsonb_build_array(value);
 end if;
 insert into public.lead_attributes(contact_id,attribute_key,value_text,value_jsonb,confidence,source,evidence,status)
 values(p_contact,p_key,case when jsonb_typeof(final_value)='string' then final_value#>>'{}' else final_value::text end,final_value,case when p_source='crm' then 1 else 0.9 end,p_source,left(p_evidence,1000),'confirmed')
 on conflict(contact_id,namespace,attribute_key) do update set value_text=excluded.value_text,value_jsonb=excluded.value_jsonb,confidence=excluded.confidence,source=excluded.source,status='confirmed',evidence=excluded.evidence,observed_at=now(),updated_at=clock_timestamp() returning * into result;
 update public.contacts set updated_at=clock_timestamp() where id=p_contact;
 return jsonb_build_object('saved',true,'attribute',to_jsonb(result));
end;$$;

-- A canonical projection keeps the existing visible fields in sync with tools.
create function public.olivia_commercial_profile(p_contact uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare profile jsonb; attrs jsonb:=public.olivia_get_attributes(p_contact); k text; tastes text:=''; objections text:=''; val text;
begin
 select coalesce(preferences->'commercial','{}') into profile from public.contacts where id=p_contact;
 foreach k in array array['preferred_products','preferred_flavors','preferred_formats','usage_preferences','interests'] loop
  if attrs ? k then
   if jsonb_typeof(attrs->k)='array' then select string_agg(value,', ') into val from jsonb_array_elements_text(attrs->k); else val:=attrs->>k; end if;
   if nullif(val,'') is not null then tastes:=concat_ws('; ',nullif(tastes,''),val); end if;
  end if;
 end loop;
 foreach k in array array['avoided_products','avoided_flavors','objections','price_objection'] loop
  if attrs ? k then
   if jsonb_typeof(attrs->k)='array' then select string_agg(value,', ') into val from jsonb_array_elements_text(attrs->k); else val:=attrs->>k; end if;
   if nullif(val,'') is not null then objections:=concat_ws('; ',nullif(objections,''),val); end if;
  end if;
 end loop;
 return coalesce(profile,'{}')||jsonb_build_object(
  'tastes',coalesce(nullif(profile->>'tastes',''),tastes),
  'objections',coalesce(nullif(profile->>'objections',''),objections),
  'buying_horizon',coalesce(nullif(profile->>'buying_horizon',''),attrs->>'buying_horizon',''));
end;$$;

create function public.olivia_agent_tool(p_contact uuid,p_conversation uuid,p_batch_ids jsonb,p_operation text,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.contacts; batch uuid[]:=array(select jsonb_array_elements_text(p_batch_ids)::uuid); msg text; evidence text; name_value text; a jsonb; tag text; action text; result jsonb:='{}'; saved jsonb:='[]'; event_key text; prior jsonb; prior_question text; campaign jsonb;
begin
 select * into c from public.contacts where id=p_contact for update;
 if not found or not exists(select 1 from public.conversations where id=p_conversation and contact_id=c.id) then raise exception 'Contact/conversation mismatch'; end if;
 if cardinality(batch)=0 or (select count(*) from public.inbound_message_buffer where id=any(batch) and contact_id=c.id and conversation_id=p_conversation and status='claimed')<>cardinality(batch) then raise exception 'Claimed batch required'; end if;
 select string_agg(normalized_text,E'\n' order by received_at,id) into msg from public.inbound_message_buffer where id=any(batch);
 if exists(select 1 from public.conversations where id=p_conversation and handoff_status in ('human','pending_human')) or exists(select 1 from public.contact_channel_consents where contact_id=c.id and channel='whatsapp' and status='revoked') or btrim(msg) ~* '^(stop|baja|unsubscribe)[ .!]*$' then return jsonb_build_object('saved',false,'reason','handoff_or_optout'); end if;
 event_key:='agent-tool:'||md5(array_to_string(array(select unnest(batch) order by 1),','))||':'||p_operation||':'||md5(p_data::text);
 select metadata->'result' into prior from public.contact_events where idempotency_key=event_key;
 if prior is not null then return prior||jsonb_build_object('duplicate',true); end if;
 if p_operation='save_name' then
  name_value:=nullif(btrim(p_data->>'name'),''); evidence:=nullif(p_data->>'evidence','');
  if name_value is null or length(name_value)>100 or evidence is null or position(lower(evidence) in lower(msg))=0 or position(lower(name_value) in lower(msg))=0 then return jsonb_build_object('saved',false,'reason','name_evidence_required'); end if;
  if msg !~* '(me llamo|mi nombre es|soy |ll[áa]mame)' and coalesce(c.preferences#>>'{olivia,pending_question}','') !~* '(nombre|llamas)' then return jsonb_build_object('saved',false,'reason','name_not_explicit'); end if;
  update public.contacts set first_name=name_value,preferences=preferences||jsonb_build_object('name_source','conversation'),updated_at=clock_timestamp() where id=c.id;
  result:=jsonb_build_object('saved',true,'first_name',name_value);
 elsif p_operation='save_atributos' then
  if jsonb_typeof(p_data)<>'array' or jsonb_array_length(p_data)>20 then raise exception 'Se espera un lote de hasta 20 atributos'; end if;
  for a in select value from jsonb_array_elements(p_data) loop
   if (a->>'attribute_key') is null or (a->>'attribute_key') not in ('preferred_products','avoided_products','preferred_flavors','avoided_flavors','preferred_formats','usage_preferences','buying_horizon','budget_range','price_objection','purchase_intent','experience','city','order_reference','order_question','interests','objections') then continue; end if;
   evidence:=nullif(a->>'evidence','');
   if evidence is null or position(lower(evidence) in lower(msg))=0 then continue; end if;
   saved:=saved||jsonb_build_array(public.olivia_record_attribute(c.id,a->>'attribute_key',a->'value_jsonb',evidence,'llm',coalesce(a->>'update_mode','merge')));
  end loop;
  result:=jsonb_build_object('saved',exists(select 1 from jsonb_array_elements(saved) x where x->>'saved'='true'),'results',saved,'attributes',public.olivia_get_attributes(c.id));
 elsif p_operation='save_tags' then
  if jsonb_typeof(p_data)<>'array' or jsonb_array_length(p_data)>10 then raise exception 'Se espera un lote de hasta 10 etiquetas'; end if;
  prior_question:=coalesce(c.preferences#>>'{olivia,pending_question}','');
  select value into campaign from public.olivia_config where key='bf2026';
  for a in select value from jsonb_array_elements(p_data) loop
   tag:=a->>'tag'; action:=coalesce(a->>'action','add'); evidence:=nullif(a->>'evidence','');
   if tag is null or tag !~ '^[a-z][a-z0-9_:-]{1,60}$' or tag ~* '(admin|permission|consent|optout|opt_out|system|qa_test)' or action not in ('add','remove') or evidence is null or position(lower(evidence) in lower(msg))=0 then continue; end if;
   if tag='bf2026_early_access' then
    if action<>'add' or not coalesce((campaign->>'registration_open')::boolean,false) then continue; end if;
    if 'bf2026_early_access'=any(c.manual_tags) then saved:=saved||jsonb_build_array(jsonb_build_object('tag',tag,'saved',true,'already_registered',true)); continue; end if;
    if not (msg ~* '(ap[úu]ntame|inscr[íi]beme|quiero (apuntarme|inscribirme|registrarme)|me quiero (apuntar|inscribir))' or (prior_question ~* '(apunt|inscrib).*(early access|acceso anticipado)' and btrim(msg) ~* '^(s[íi]|vale|ok|de acuerdo|claro|perfecto|adelante)([ ,.!]|$)')) then continue; end if;
    insert into public.contact_channel_consents(contact_id,channel,status,source,evidence) values(c.id,'whatsapp','granted','conversation',jsonb_build_object('request',left(msg,1000),'offer',prior_question,'purpose','bf2026_early_access'))
    on conflict(contact_id,channel) do update set status='granted',recorded_at=clock_timestamp(),source='conversation',evidence=excluded.evidence;
    update public.contacts set preferences=jsonb_set(preferences,'{early_access}',jsonb_build_object('source','conversation','welcomed_by','olivia','registered_at',now())),manual_tags=array(select distinct unnest(manual_tags||array[tag])),updated_at=clock_timestamp() where id=c.id;
    result:=result||jsonb_build_object('registered',true,'welcome_by','olivia');
   else
    update public.contacts set manual_tags=case when action='remove' then array_remove(manual_tags,tag) else array(select distinct unnest(manual_tags||array[tag])) end,updated_at=clock_timestamp() where id=c.id;
   end if;
   saved:=saved||jsonb_build_array(jsonb_build_object('tag',tag,'action',action,'saved',true));
  end loop;
  result:=result||jsonb_build_object('saved',jsonb_array_length(saved)>0,'results',saved);
 else raise exception 'Unsupported agent tool'; end if;
 insert into public.contact_events(contact_id,event_type,source,metadata,idempotency_key) values(c.id,'agent_tool','olivia',jsonb_build_object('operation',p_operation,'batch_ids',p_batch_ids,'data',p_data,'result',result),event_key);
 return result;
end;$$;

create function public.olivia_save_attribute_crm(p_contact uuid,p_key text,p_value jsonb) returns jsonb language sql security invoker set search_path='' as $$
 select public.olivia_record_attribute(p_contact,p_key,p_value,null,'crm','replace');
$$;

revoke all on function public.olivia_get_attributes(uuid),public.olivia_record_attribute(uuid,text,jsonb,text,text,text),public.olivia_commercial_profile(uuid),public.olivia_agent_tool(uuid,uuid,jsonb,text,jsonb),public.olivia_save_attribute_crm(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.olivia_get_attributes(uuid),public.olivia_record_attribute(uuid,text,jsonb,text,text,text),public.olivia_commercial_profile(uuid),public.olivia_agent_tool(uuid,uuid,jsonb,text,jsonb),public.olivia_save_attribute_crm(uuid,text,jsonb) to service_role;

create function public.olivia_entry_to_attribute() returns trigger language plpgsql security invoker set search_path='' as $$
declare label text; key_value text; mode_value text:=case when new.status='cancelled' then 'remove' else 'merge' end;
begin
 if new.kind='purchase' then return new; end if;
 if new.product_id is not null then select name into label from public.catalog_products where id=new.product_id; end if;
 if new.kind='order_inquiry' then
  if new.reference<>'' then perform public.olivia_record_attribute(new.contact_id,'order_reference',jsonb_build_array(new.reference),new.evidence,case when new.source='crm' then 'crm' else 'llm' end,mode_value); end if;
  perform public.olivia_record_attribute(new.contact_id,'order_question',to_jsonb(new.details),new.evidence,case when new.source='crm' then 'crm' else 'llm' end,'replace');
 else
  key_value:=case when new.kind='avoid' then case when label is null then 'objections' else 'avoided_products' end else case when label is null then 'interests' else 'preferred_products' end end;
  perform public.olivia_record_attribute(new.contact_id,key_value,jsonb_build_array(coalesce(label,new.details)),new.evidence,case when new.source='crm' then 'crm' else 'llm' end,mode_value);
 end if;
 return new;
end;$$;
revoke all on function public.olivia_entry_to_attribute() from public,anon,authenticated;
create trigger olivia_commercial_entry_attributes after insert or update on public.contact_commercial_entries for each row execute function public.olivia_entry_to_attribute();

create function public.olivia_store_lead_state(p_contact uuid,p_decision jsonb) returns void language plpgsql security invoker set search_path='' as $$
declare c public.contacts; score_value int; score_reason text;
begin
 select * into c from public.contacts where id=p_contact;
 score_value:=case when coalesce(p_decision->>'lead_score','') ~ '^[0-9]{1,3}$' then greatest(0,least(100,(p_decision->>'lead_score')::int)) else (public.olivia_contact_score(c.id)->>'automatic')::int end;
 score_reason:=left(coalesce(nullif(p_decision->>'score_reason',''),'Valoración comercial según la conversación y los hechos confirmados'),500);
 if coalesce((p_decision->>'opt_out')::boolean,false) and coalesce(p_decision->>'opt_out_scope','whatsapp') in ('whatsapp','all') then score_value:=0; score_reason:='Comunicaciones de WhatsApp revocadas'; end if;
 insert into public.lead_states(contact_id,phase,temperature,lead_score,score_reason,summary,pending_question,last_intent)
 values(c.id,c.stage,case when p_decision->>'temperature' in ('cold','warm','hot') then p_decision->>'temperature' else 'cold' end,score_value,score_reason,left(coalesce(p_decision->>'summary',''),3000),left(coalesce(p_decision->>'pending_question',''),500),p_decision->>'intent')
 on conflict(contact_id) do update set phase=excluded.phase,temperature=excluded.temperature,lead_score=excluded.lead_score,score_reason=excluded.score_reason,summary=excluded.summary,pending_question=excluded.pending_question,last_intent=excluded.last_intent,updated_at=clock_timestamp();
end;$$;
revoke all on function public.olivia_store_lead_state(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.olivia_store_lead_state(uuid,jsonb) to service_role;

-- Migrate previously confirmed commercial facts, including the collagen test.
do $$
declare e public.contact_commercial_entries; label text; key_value text;
begin
 for e in select * from public.contact_commercial_entries where kind<>'purchase' and status<>'cancelled' order by updated_at loop
  label:=null;
  if e.product_id is not null then select name into label from public.catalog_products where id=e.product_id; end if;
  if e.kind='order_inquiry' then
   if e.reference<>'' then perform public.olivia_record_attribute(e.contact_id,'order_reference',jsonb_build_array(e.reference),e.evidence,'import','merge'); end if;
   perform public.olivia_record_attribute(e.contact_id,'order_question',to_jsonb(e.details),e.evidence,'import','replace');
  else
   key_value:=case when e.kind='avoid' then case when label is null then 'objections' else 'avoided_products' end else case when label is null then 'interests' else 'preferred_products' end end;
   perform public.olivia_record_attribute(e.contact_id,key_value,jsonb_build_array(coalesce(label,e.details)),e.evidence,'import','merge');
  end if;
 end loop;
end;$$;
