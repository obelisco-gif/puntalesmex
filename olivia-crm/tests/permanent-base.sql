begin;
do $test$
declare cid uuid; vid uuid; v_payload text; r jsonb; v_id uuid;
begin
 select c.id,v.id into cid,vid from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id='46e8999c-a9ed-486b-8426-c8b07f2aa87a' limit 1;
 if vid is null then raise exception 'Missing QA fixture'; end if;
 v_payload:=encode(convert_to(jsonb_build_object('contact_id',cid,'conversation_id',vid,'decision',jsonb_build_object('knowledge_packages','[]'::jsonb,'product_ids','[]'::jsonb))::text,'utf8'),'base64');
 insert into public.product_documents(title,content,document_type,approval_status,routing_packages)
 values('QA permanent base','QA base version 1','source','approved',array['always']) returning id into v_id;
 select q.context into r from (select public.olivia_context_v2_b64(v_payload) || jsonb_build_object('base_documents',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])) as context)q;
 if not exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text and x->>'content'='QA base version 1') then raise exception 'First agent missing base'; end if;
 select q.context into r from (with selected as(select public.olivia_response_context_b64(v_payload) as ctx), base as(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])
select selected.ctx || jsonb_build_object('base_documents',base.docs,'documents',
coalesce((select jsonb_agg(doc) from jsonb_array_elements(coalesce(selected.ctx->'documents','[]'::jsonb)) doc
where not exists(select 1 from jsonb_array_elements(base.docs) b where b->>'id'=doc->>'id')),'[]'::jsonb)) as context
from selected cross join base)q;
 if not exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text) then raise exception 'Second agent missing base'; end if;
 if exists(select 1 from jsonb_array_elements(r->'documents')x where x->>'id'=v_id::text) then raise exception 'Base injected twice'; end if;
 update public.product_documents set content='QA base version 2' where id=v_id;
 select q.context into r from (select public.olivia_context_v2_b64(v_payload) || jsonb_build_object('base_documents',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])) as context)q;
 if not exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text and x->>'content'='QA base version 2') then raise exception 'Router stale after edit'; end if;
 select q.context into r from (with selected as(select public.olivia_response_context_b64(v_payload) as ctx), base as(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])
select selected.ctx || jsonb_build_object('base_documents',base.docs,'documents',
coalesce((select jsonb_agg(doc) from jsonb_array_elements(coalesce(selected.ctx->'documents','[]'::jsonb)) doc
where not exists(select 1 from jsonb_array_elements(base.docs) b where b->>'id'=doc->>'id')),'[]'::jsonb)) as context
from selected cross join base)q;
 if not exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text and x->>'content'='QA base version 2') then raise exception 'Writer stale after edit'; end if;
 update public.product_documents set approval_status='archived' where id=v_id;
 select q.context into r from (with selected as(select public.olivia_response_context_b64(v_payload) as ctx), base as(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])
select selected.ctx || jsonb_build_object('base_documents',base.docs,'documents',
coalesce((select jsonb_agg(doc) from jsonb_array_elements(coalesce(selected.ctx->'documents','[]'::jsonb)) doc
where not exists(select 1 from jsonb_array_elements(base.docs) b where b->>'id'=doc->>'id')),'[]'::jsonb)) as context
from selected cross join base)q;
 if exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text) then raise exception 'Archived base leaked'; end if;
 update public.product_documents set approval_status='approved',routing_packages=array['always','internal_ops'] where id=v_id;
 select q.context into r from (select public.olivia_context_v2_b64(v_payload) || jsonb_build_object('base_documents',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])) as context)q;
 if exists(select 1 from jsonb_array_elements(r->'base_documents')x where x->>'id'=v_id::text) then raise exception 'Internal base leaked'; end if;
end;
$test$;
rollback;
select 'PASS: base delivered to both agents without selection, one copy, fresh after edit, archived/internal excluded' as result;
