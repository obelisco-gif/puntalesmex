-- Primera etapa
select public.olivia_context_v2_b64($1) || jsonb_build_object('base_documents',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])) as context;

-- Segunda etapa
with selected as(select public.olivia_response_context_b64($1) as ctx), base as(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'content',content,'source_url',source_url,'updated_at',updated_at) order by updated_at,id),'[]'::jsonb) as docs
from public.product_documents where approval_status='approved' and routing_packages && array['always']
and not routing_packages && array['internal_ops'])
select selected.ctx || jsonb_build_object('base_documents',base.docs,'documents',
coalesce((select jsonb_agg(doc) from jsonb_array_elements(coalesce(selected.ctx->'documents','[]'::jsonb)) doc
where not exists(select 1 from jsonb_array_elements(base.docs) b where b->>'id'=doc->>'id')),'[]'::jsonb)) as context
from selected cross join base;

