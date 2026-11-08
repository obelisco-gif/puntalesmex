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
 'purchase_history',public.olivia_purchase_history(c.id),
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
 'products',coalesce((select jsonb_agg(public.olivia_catalog_product_context(id,false)) from public.catalog_products where status='publish'),'[]'::jsonb),
 'now',now()) into result
 from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id=(p->>'contact_id')::uuid and v.id=(p->>'conversation_id')::uuid;
 return coalesce(result,'{}'::jsonb);
end;$function$;

CREATE OR REPLACE FUNCTION public.olivia_response_context_b64(p_payload_b64 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  'products',coalesce((select jsonb_agg(public.olivia_catalog_product_context(id,true))
    from public.catalog_products where id=any(products)),'[]'::jsonb)
 ) into result;
 return result;
end; $function$;

revoke all on function public.olivia_context_v2_b64(text),public.olivia_response_context_b64(text) from public,anon,authenticated;
grant execute on function public.olivia_context_v2_b64(text),public.olivia_response_context_b64(text) to service_role;
