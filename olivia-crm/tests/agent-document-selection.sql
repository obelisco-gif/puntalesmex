begin;
do $t$
declare cid uuid;vid uuid;pid uuid;other_pid uuid;tone uuid;own uuid;campaign uuid;usage uuid;foreign_doc uuid;internal_doc uuid;draft uuid;p text;r jsonb;w jsonb;
begin
 insert into public.contacts(email,first_name,manual_tags,preferences) values('selector@example.invalid','Demo',array['qa_test'],'{"olivia":{"summary":"Busca colágeno"}}') returning id into cid;
 insert into public.conversations(contact_id,channel) values(cid,'whatsapp') returning id into vid;
 insert into public.messages(conversation_id,direction,body) values(vid,'inbound','Me interesa el colágeno');
 insert into public.catalog_products(woocommerce_product_id,name,status,product_type) values(900001,'Producto A','publish','variable') returning id into pid;
 insert into public.catalog_products(woocommerce_product_id,name,status) values(900002,'Producto B','publish') returning id into other_pid;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages) values('Voz','Tono común','sales','approved',array['always']) returning id into tone;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages) values('Cualificación','Solo decide el primer agente','sales','approved',array['orchestrator']) returning id into own;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages) values('Campaña','Condiciones editables','sales','approved',array['black_friday']) returning id into campaign;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages,catalog_product_id) values('Uso A','Instrucciones A','usage','approved',array['usage'],pid) returning id into usage;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages,catalog_product_id) values('Uso B','Instrucciones B','usage','approved',array['usage'],other_pid) returning id into foreign_doc;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages) values('Interno','No compartir','source','approved',array['internal_ops']) returning id into internal_doc;
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages) values('Borrador','No aprobar','source','draft',array['usage']) returning id into draft;
 p:=encode(convert_to(jsonb_build_object('contact_id',cid,'conversation_id',vid,'batch_text','Me interesa el colágeno','decision',jsonb_build_object('product_ids',jsonb_build_array(pid),'selected_document_ids',jsonb_build_array(usage,foreign_doc,own,internal_doc,draft),'knowledge_packages',jsonb_build_array('black_friday','usage')))::text,'utf8'),'base64');
 r:=public.olivia_orchestrator_context_b64(p);w:=public.olivia_writer_context_b64(p);
 if not exists(select 1 from jsonb_array_elements(r->'orchestration_documents')x where x->>'id'=own::text) then raise exception 'Router missing own policy';end if;
 if exists(select 1 from jsonb_array_elements(r->'document_index')x where x->>'id' in(own::text,internal_doc::text,draft::text) or x?'content') then raise exception 'Router leaked own/internal/full text into index';end if;
 if exists(select 1 from jsonb_array_elements(r->'document_index')x where x->>'description' like '%Instrucciones A%' or x->>'description' like '%Condiciones editables%') then raise exception 'Index contains full document body';end if;
 if not exists(select 1 from jsonb_array_elements(r->'document_index')x where x->>'id'=campaign::text and x?'description') then raise exception 'Missing descriptive campaign index';end if;
 if jsonb_array_length(w->'documents')<>1 or w#>>'{documents,0,id}'<>usage::text then raise exception 'Writer must receive exact approved selected document for selected product';end if;
 if exists(select 1 from jsonb_array_elements(w->'documents')x where x->>'id'=campaign::text) then raise exception 'Unselected campaign injected';end if;
 if w?'document_index' or w?'orchestration_documents' then raise exception 'Writer got router library';end if;
 if not exists(select 1 from jsonb_array_elements(w->'base_documents')x where x->>'id'=tone::text) then raise exception 'Writer missing permanent voice';end if;
 if jsonb_array_length(w->'products')<>1 or w#>>'{products,0,id}'<>pid::text then raise exception 'Wrong product selection';end if;
 foreach p in array array['contact','history','attributes','attribute_records','lead_state','commercial_profile','commercial_entries','score','purchase_history','channel_consents','early_access_registered','email_signup'] loop
 if not (r?p and w?p) or r->p is distinct from w->p then raise exception 'Shared context lost: %',p;end if;
 end loop;
 update public.product_documents set content='Nueva instrucción A' where id=usage;
 p:=encode(convert_to(jsonb_build_object('contact_id',cid,'conversation_id',vid,'decision',jsonb_build_object('product_ids',jsonb_build_array(pid),'selected_document_ids',jsonb_build_array(usage)))::text,'utf8'),'base64');
 w:=public.olivia_writer_context_b64(p);if w#>>'{documents,0,content}'<>'Nueva instrucción A' then raise exception 'Selected document stale';end if;
 update public.product_documents set approval_status='archived' where id=usage;
 w:=public.olivia_writer_context_b64(p);if jsonb_array_length(w->'documents')<>0 then raise exception 'Archived document leaked';end if;
 if has_function_privilege('anon','public.olivia_orchestrator_context_b64(text)','execute') or has_function_privilege('authenticated','public.olivia_writer_context_b64(text)','execute') then raise exception 'Private context exposed';end if;
end;$t$;
rollback;
select 'PASS: shared lead context, router-only policies and descriptive index, exact selected writer docs, product isolation, no automatic campaign, live edits and private access' as result;
