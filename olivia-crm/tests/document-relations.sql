begin;
do $test$
declare a uuid; b uuid; ab uuid; only_b uuid; general uuid; hidden uuid; draft_a uuid; r jsonb; payload jsonb; cid uuid; vid uuid; arr text[];
begin
 select id into a from public.catalog_products order by id limit 1;
 select id into b from public.catalog_products where id<>a order by id limit 1;
 select c.id,v.id into cid,vid from public.contacts c join public.conversations v on v.contact_id=c.id
 where c.id='46e8999c-a9ed-486b-8426-c8b07f2aa87a' limit 1;
 if a is null or b is null or vid is null then raise exception 'Missing test fixtures'; end if;
 r:=public.save_olivia_document(jsonb_build_object('title','QA multi product','content','QA internal temporary','approval_status','approved','routing_packages',jsonb_build_array('commercial','qa_custom'),'catalog_product_ids',jsonb_build_array(a,b,a)));
 ab:=(r->>'id')::uuid;
 if jsonb_array_length(r->'catalog_product_ids')<>2 then raise exception 'Product deduplication failed'; end if;
 if (select count(*) from public.product_document_products where document_id=ab)<>2 then raise exception 'Multi product save failed'; end if;
 r:=public.save_olivia_document(jsonb_build_object('title','QA B only','content','QA','approval_status','approved','routing_packages',jsonb_build_array('commercial'),'catalog_product_ids',jsonb_build_array(b)));
 only_b:=(r->>'id')::uuid;
 r:=public.save_olivia_document(jsonb_build_object('title','QA general custom','content','QA','approval_status','approved','routing_packages',jsonb_build_array('qa_custom'),'catalog_product_ids','[]'::jsonb));
 general:=(r->>'id')::uuid;
 r:=public.save_olivia_document(jsonb_build_object('title','QA hidden','content','QA','approval_status','approved','routing_packages',jsonb_build_array('internal_ops','always'),'catalog_product_ids',jsonb_build_array(a)));
 hidden:=(r->>'id')::uuid;
 r:=public.save_olivia_document(jsonb_build_object('title','QA draft','content','QA','approval_status','draft','routing_packages',jsonb_build_array('commercial'),'catalog_product_ids',jsonb_build_array(a)));
 draft_a:=(r->>'id')::uuid;
 payload:=jsonb_build_object('contact_id',cid,'conversation_id',vid,'decision',jsonb_build_object('knowledge_packages',jsonb_build_array('commercial'),'product_ids',jsonb_build_array(a)));
 r:=public.olivia_response_context_b64(encode(convert_to(payload::text,'utf8'),'base64'));
 arr:=array(select x->>'id' from jsonb_array_elements(r->'documents')x);
 if not ab::text=any(arr) then raise exception 'Related product document missing'; end if;
 if only_b::text=any(arr) or hidden::text=any(arr) or draft_a::text=any(arr) then raise exception 'Wrong product or hidden document leaked'; end if;
 payload:=jsonb_set(payload,'{decision}',jsonb_build_object('knowledge_packages',jsonb_build_array('qa_custom'),'product_ids','[]'::jsonb));
 r:=public.olivia_response_context_b64(encode(convert_to(payload::text,'utf8'),'base64'));
 arr:=array(select x->>'id' from jsonb_array_elements(r->'documents')x);
 if not general::text=any(arr) or ab::text=any(arr) then raise exception 'General topic scoping failed'; end if;
 r:=public.olivia_context_v2_b64(encode(convert_to(payload::text,'utf8'),'base64'));
 if not exists(select 1 from jsonb_array_elements(r->'document_index')x where x->>'id'=ab::text and jsonb_array_length(x->'product_ids')=2) then raise exception 'Router product index missing'; end if;
 if exists(select 1 from jsonb_array_elements(r->'document_index')x where x->>'id'=hidden::text) then raise exception 'Internal document index leaked'; end if;
 r:=public.save_olivia_document(jsonb_build_object('title','QA changed relations','content','QA','approval_status','draft','routing_packages',jsonb_build_array('usage','qa_custom'),'catalog_product_ids',jsonb_build_array(b)),ab);
 if (select count(*) from public.product_document_products where document_id=ab)<>1 or (select catalog_product_id from public.product_documents where id=ab)<>b then raise exception 'Atomic relationship replacement failed'; end if;
 begin
  perform public.save_olivia_document(jsonb_build_object('title','QA invalid','content','QA','routing_packages',jsonb_build_array('commercial'),'catalog_product_ids',jsonb_build_array(gen_random_uuid())),ab);
  raise exception 'Invalid product accepted';
 exception when invalid_parameter_value then null; end;
 if (select title from public.product_documents where id=ab)<>'QA changed relations' then raise exception 'Invalid save modified document'; end if;
 if has_function_privilege('anon','public.save_olivia_document(jsonb,uuid)','execute') or has_function_privilege('authenticated','public.save_olivia_document(jsonb,uuid)','execute') then raise exception 'Public write RPC permission leaked'; end if;
end;
$test$;
rollback;
select 'PASS: multi-product save, deduplication, atomic edits, custom topics, product scoping, hidden/draft exclusion, router index and restricted RPC' as result;
