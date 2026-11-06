-- Stage-specific documentation; shared live lead context remains unchanged.
create or replace function public.olivia_orchestrator_context_b64(p_payload_b64 text)
returns jsonb language plpgsql security invoker set search_path='' as $fn$
declare ctx jsonb;
begin
 ctx:=public.olivia_context_v2_b64(p_payload_b64);
 if ctx='{}'::jsonb then return ctx;end if;
 return ctx||jsonb_build_object(
 'base_documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'content',d.content,'updated_at',d.updated_at) order by d.id)
 from public.product_documents d where d.approval_status='approved' and d.routing_packages&&array['always'] and not d.routing_packages&&array['internal_ops','orchestrator']),'[]'::jsonb),
 'orchestration_documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'content',d.content,'updated_at',d.updated_at) order by d.id)
 from public.product_documents d where d.approval_status='approved' and d.routing_packages&&array['orchestrator'] and not d.routing_packages&&array['internal_ops']),'[]'::jsonb),
 'document_index',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'document_key',d.document_key,'title',d.title,
 'description',d.title||'. Categoría: '||d.document_type||'. Temas: '||array_to_string(d.routing_packages,', '),'packages',d.routing_packages,
 'product_ids',public.olivia_document_product_ids(d.id,d.catalog_product_id),'always_in_writer',d.routing_packages&&array['always']) order by d.title,d.id)
 from public.product_documents d where d.approval_status='approved' and not d.routing_packages&&array['internal_ops','orchestrator']),'[]'::jsonb));
end;$fn$;
revoke all on function public.olivia_orchestrator_context_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_orchestrator_context_b64(text) to service_role;

create or replace function public.olivia_writer_context_b64(p_payload_b64 text)
returns jsonb language plpgsql security invoker set search_path='' as $fn$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;ctx jsonb;d jsonb:=coalesce(p->'decision','{}');products uuid[];docs jsonb;base jsonb;
begin
 ctx:=public.olivia_context_v2_b64(p_payload_b64);
 if ctx='{}'::jsonb then raise exception 'Contact/conversation mismatch';end if;
 products:=array(select cp.id from public.catalog_products cp where cp.status='publish'
 and cp.id::text in(select jsonb_array_elements_text(coalesce(d->'product_ids','[]'))));
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'title',q.title,'content',q.content,'source_url',q.source_url,'packages',q.routing_packages,'product_ids',q.linked_ids,'updated_at',q.updated_at) order by q.title,q.id),'[]'::jsonb) into docs
 from(select pd.*,public.olivia_document_product_ids(pd.id,pd.catalog_product_id) as linked_ids from public.product_documents pd
 where pd.approval_status='approved' and not pd.routing_packages&&array['internal_ops','orchestrator','always'])q
 where q.id::text in(select jsonb_array_elements_text(coalesce(d->'selected_document_ids','[]')))
 and (cardinality(q.linked_ids)=0 or q.linked_ids&&products);
 select coalesce(jsonb_agg(jsonb_build_object('id',pd.id,'title',pd.title,'content',pd.content,'source_url',pd.source_url,'updated_at',pd.updated_at) order by pd.id),'[]'::jsonb) into base
 from public.product_documents pd where pd.approval_status='approved' and pd.routing_packages&&array['always']
 and not pd.routing_packages&&array['internal_ops','orchestrator']
 and cardinality(public.olivia_document_product_ids(pd.id,pd.catalog_product_id))=0;
 return (ctx-'document_index'-'products'-'base_documents'-'orchestration_documents')||jsonb_build_object(
 'decision',d,'base_documents',base,'documents',docs,
 'products',coalesce((select jsonb_agg(public.olivia_catalog_product_context(id,true)) from public.catalog_products where id=any(products)),'[]'::jsonb),
 'document_selection',jsonb_build_object('requested_ids',coalesce(d->'selected_document_ids','[]'),'injected_ids',(select coalesce(jsonb_agg(x->'id'),'[]') from jsonb_array_elements(docs)x),'permanent_ids',(select coalesce(jsonb_agg(x->'id'),'[]') from jsonb_array_elements(base)x)));
end;$fn$;
revoke all on function public.olivia_writer_context_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_writer_context_b64(text) to service_role;
