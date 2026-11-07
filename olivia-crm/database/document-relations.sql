create table public.product_document_products (
 document_id uuid not null references public.product_documents(id) on delete cascade,
 catalog_product_id uuid not null references public.catalog_products(id) on delete cascade,
 primary key(document_id,catalog_product_id)
);
create index product_document_products_product_idx on public.product_document_products(catalog_product_id,document_id);
alter table public.product_document_products enable row level security;
revoke all on public.product_document_products from public,anon,authenticated;
grant all on public.product_document_products to service_role;
insert into public.product_document_products(document_id,catalog_product_id)
 select id,catalog_product_id from public.product_documents where catalog_product_id is not null
 on conflict do nothing;

-- Keep the legacy pointer for compatibility without deleting a whole document
-- when one linked product is removed.
alter table public.product_documents drop constraint product_documents_catalog_product_id_fkey;
alter table public.product_documents add constraint product_documents_catalog_product_id_fkey
 foreign key(catalog_product_id) references public.catalog_products(id) on delete set null;

create or replace function public.olivia_document_product_ids(p_document_id uuid,p_legacy_id uuid default null)
returns uuid[] language sql stable security invoker set search_path='' as $$
 select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) from (
 select catalog_product_id as id from public.product_document_products where document_id=p_document_id
 union select p_legacy_id where p_legacy_id is not null
 ) linked;
$$;
revoke all on function public.olivia_document_product_ids(uuid,uuid) from public,anon,authenticated;
grant execute on function public.olivia_document_product_ids(uuid,uuid) to service_role;

-- Topic and product relations are independent. Preserve existing routing topics.
update public.product_documents set routing_packages=array(
 select distinct t from unnest(routing_packages||array[
 case document_type when 'sales' then 'commercial' when 'usage' then 'usage'
 when 'safety' then 'safety' when 'comparison' then 'comparison' when 'faq' then 'faq' else 'reference' end
 ]) t order by t
) where not routing_packages && array['internal_ops'];

create or replace function public.save_olivia_document(p_document jsonb,p_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_id uuid:=p_id; v_old public.product_documents%rowtype; v_products uuid[]; v_topics text[]; v_status text; v_type text;
begin
 if p_id is not null then
  select * into v_old from public.product_documents where id=p_id for update;
  if not found then raise exception 'Documento no encontrado' using errcode='P0002'; end if;
 end if;
 if jsonb_typeof(p_document->'title') is distinct from 'string' or length(btrim(p_document->>'title')) not between 1 and 240
 or jsonb_typeof(p_document->'content') is distinct from 'string' or length(btrim(p_document->>'content')) not between 1 and 100000
 then raise exception 'Indica título y contenido válidos' using errcode='22023'; end if;
 if jsonb_typeof(p_document->'catalog_product_ids') is distinct from 'array' or jsonb_typeof(p_document->'routing_packages') is distinct from 'array'
 then raise exception 'Productos y temas deben ser listas' using errcode='22023'; end if;
 v_products:=array(select distinct x::uuid from jsonb_array_elements_text(p_document->'catalog_product_ids') x order by x::uuid);
 v_topics:=array(select distinct btrim(x) from jsonb_array_elements_text(p_document->'routing_packages') x where btrim(x)<>'' order by btrim(x));
 if cardinality(v_products)>100 or cardinality(v_topics) not between 1 and 20 or exists(select 1 from unnest(v_topics)t where length(t)>64)
 then raise exception 'Selecciona entre 1 y 20 temas y hasta 100 productos' using errcode='22023'; end if;
 if exists(select 1 from unnest(v_products)x where not exists(select 1 from public.catalog_products where id=x))
 then raise exception 'Hay productos que ya no existen en el catálogo' using errcode='22023'; end if;
 v_status:=coalesce(p_document->>'approval_status',v_old.approval_status,'draft');
 if v_status not in ('draft','approved','archived') then raise exception 'Estado no válido' using errcode='22023'; end if;
 v_type:=coalesce(v_old.document_type,'source');
 if p_id is null then
  insert into public.product_documents(title,content,source_url,approval_status,document_type,routing_packages,catalog_product_id,reviewed_at)
  values(btrim(p_document->>'title'),btrim(p_document->>'content'),nullif(btrim(p_document->>'source_url'),''),v_status,v_type,v_topics,v_products[1],case when v_status='approved' then now() end)
  returning id into v_id;
 else
  update public.product_documents set title=btrim(p_document->>'title'),content=btrim(p_document->>'content'),
   source_url=nullif(btrim(p_document->>'source_url'),''),approval_status=v_status,routing_packages=v_topics,catalog_product_id=v_products[1],
   reviewed_at=case when v_status='approved' then now() when v_status='draft' then null else reviewed_at end,updated_at=now() where id=v_id;
 end if;
 delete from public.product_document_products where document_id=v_id;
 insert into public.product_document_products(document_id,catalog_product_id) select v_id,x from unnest(v_products)x;
 return (select to_jsonb(d)||jsonb_build_object('catalog_product_ids',v_products) from public.product_documents d where id=v_id);
end; $$;
revoke all on function public.save_olivia_document(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.save_olivia_document(jsonb,uuid) to service_role;

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
 'contact',jsonb_build_object('first_name',c.first_name,'email',c.email,'phone',c.phone,'stage',c.stage,'source',c.source,'tags',c.manual_tags,'preferences',c.preferences),
 'lead_state',coalesce(c.preferences->'olivia','{}'::jsonb),
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


CREATE OR REPLACE FUNCTION public.get_olivia_context_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p jsonb;
  v_result jsonb;
begin
  p := convert_from(decode(p_payload_b64, 'base64'), 'utf8')::jsonb;
  select jsonb_build_object(
    'contact_id', (p->>'contact_id')::uuid,
    'conversation_id', (p->>'conversation_id')::uuid,
    'batch_text', p->>'batch_text',
    'batch_ids', coalesce(p->'batch_ids', '[]'::jsonb),
    'contact', coalesce(to_jsonb(c), '{}'::jsonb),
    'history', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.created_at asc)
      from (
        select direction, body, created_at
        from public.messages
        where conversation_id = (p->>'conversation_id')::uuid
        order by created_at desc
        limit 12
      ) h
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select id, name, slug, permalink, price, currency, on_sale, stock_status,
               short_description, assistant_summary, usage_notes, safety_notes, recommendation_tags
        from public.catalog_products
        where status = 'publish' and purchasable = true
        order by updated_at desc
        limit 30
      ) x
    ), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(to_jsonb(d))
      from (
        select id, catalog_product_id, public.olivia_document_product_ids(id,catalog_product_id) as catalog_product_ids, routing_packages, document_type, title, content, source_url
        from public.product_documents
        where approval_status = 'approved' and not routing_packages && array['internal_ops']
        order by updated_at desc
        limit 20
      ) d
    ), '[]'::jsonb)
  ) into v_result
  from public.contacts c
  where c.id = (p->>'contact_id')::uuid;
  return coalesce(v_result, '{}'::jsonb);
end;
$function$;


create or replace function public.olivia_response_context_b64(p_payload_b64 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p jsonb:=convert_from(decode(p_payload_b64,'base64'),'utf8')::jsonb;
 ctx jsonb; d jsonb:=coalesce(p->'decision','{}'); packages text[]; products uuid[]; result jsonb;
begin
 ctx:=public.olivia_context_v2_b64(p_payload_b64);
 if ctx='{}'::jsonb then raise exception 'Contact/conversation mismatch'; end if;
 packages:=array(select jsonb_array_elements_text(coalesce(d->'knowledge_packages','[]')));
 -- Validate product IDs again inside the database before retrieving documents.
 products:=array(select cp.id from public.catalog_products cp where cp.status='publish' and cp.id::text in
 (select jsonb_array_elements_text(coalesce(d->'product_ids','[]'))));
 select (ctx-'document_index'-'products')||jsonb_build_object(
  'decision',d,
  'documents',coalesce((select jsonb_agg(jsonb_build_object('id',docs.id,'title',docs.title,'content',docs.content,
    'packages',docs.routing_packages,'product_ids',docs.linked_ids,'source_url',docs.source_url))
   from (select pd.*,public.olivia_document_product_ids(pd.id,pd.catalog_product_id) as linked_ids
    from public.product_documents pd where pd.approval_status='approved'
    and not pd.routing_packages && array['internal_ops'])docs
   where (cardinality(docs.linked_ids)=0 and (docs.routing_packages && array['always','black_friday'] or docs.routing_packages && packages))
    or docs.linked_ids && products),'[]'::jsonb),
  'products',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'url',permalink,'price',price,'currency',currency,
    'stock_status',stock_status,'stock_quantity',stock_quantity,'synced_at',synced_at,'product_type',product_type))
    from public.catalog_products where id=any(products)),'[]'::jsonb)
 ) into result;
 return result;
end; $$;
revoke all on function public.olivia_response_context_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_response_context_b64(text) to service_role;
notify pgrst,'reload schema';
