begin;
do $$
declare p uuid;other uuid;c uuid;chat uuid;snapshot jsonb;r jsonb;ctx jsonb;
begin
 select catalog_product_id into p from public.olivia_sync_catalog_parent('{"woocommerce_product_id":999002,"name":"Parent wrapper","product_type":"variable","expected_variation_ids":[999021]}'::jsonb);
 if (select variations_sync_status from public.catalog_products where id=p)<>'pending' then raise exception 'Parent wrapper did not mark pending'; end if;
 update public.catalog_products set internal_notes='Keep me' where id=p;
 perform public.olivia_sync_catalog_parent('{"woocommerce_product_id":999002,"name":"Updated parent","product_type":"simple"}'::jsonb);
 if (select internal_notes='Keep me' and variations_sync_status='not_applicable' and name='Updated parent' from public.catalog_products where id=p) is not true then raise exception 'Parent wrapper update lost notes'; end if;
 insert into public.catalog_products(woocommerce_product_id,name,product_type,internal_notes) values(999001,'Variable de prueba','variable','Conservar nota') returning id into p;
 snapshot:=jsonb_build_object('catalog_product_id',p,'woocommerce_product_id',999001,'requested_at',clock_timestamp(),'complete',true,'expected_ids',jsonb_build_array(999011,999012),'variations',jsonb_build_array(
 jsonb_build_object('woocommerce_variation_id',999011,'name','300g','status','publish','price',14.5,'regular_price',15,'sale_price',14.5,'on_sale',true,'purchasable',true,'stock_status','instock','stock_quantity',0,'attributes',jsonb_build_array(jsonb_build_object('name','Formato','option','300g'))),
 jsonb_build_object('woocommerce_variation_id',999012,'name','500g','status','publish','price',22.5,'purchasable',true,'stock_status','outofstock','stock_quantity',null,'attributes',jsonb_build_array(jsonb_build_object('name','Formato','option','500g')))));
 r:=public.sync_catalog_variations(snapshot);
 if (r->>'upserted')::integer<>2 or (select internal_notes from public.catalog_products where id=p)<>'Conservar nota' then raise exception 'Snapshot sync failed or manual notes overwritten'; end if;
 if not (public.sync_catalog_variations(snapshot)->>'skipped_stale')::boolean then raise exception 'Stale replay overwrote newer sync'; end if;
 ctx:=public.olivia_catalog_product_context(p,true);
 if jsonb_array_length(ctx->'variations')<>2 or ctx->'variations'->0->>'stock_quantity'<>'0' or ctx->'variations'->1->>'stock_quantity' is not null then raise exception 'Variant stock lost zero/null distinction'; end if;
 begin
 perform public.sync_catalog_variations(jsonb_set(snapshot,'{expected_ids}','[999011]'::jsonb)||jsonb_build_object('requested_at',clock_timestamp()));
 raise exception 'Incomplete snapshot accepted';
 exception when others then if sqlerrm not like '%no coincide%' then raise; end if;end;
 if (select count(*) from public.catalog_variations where catalog_product_id=p and is_active)<>2 then raise exception 'Incomplete snapshot retired valid variants'; end if;
 snapshot:=snapshot||jsonb_build_object('requested_at',clock_timestamp(),'expected_ids',jsonb_build_array(999011),'variations',jsonb_build_array(snapshot->'variations'->0));
 r:=public.sync_catalog_variations(snapshot);
 if (r->>'retired')::integer<>1 or (select is_active from public.catalog_variations where woocommerce_variation_id=999012) then raise exception 'Removed variant not retired'; end if;
 insert into public.contacts(email,source) values('variants@example.invalid','crm') returning id into c;
 insert into public.conversations(contact_id,channel) values(c,'whatsapp') returning id into chat;
 ctx:=public.olivia_response_context_b64(encode(convert_to(jsonb_build_object('contact_id',c,'conversation_id',chat,'decision',jsonb_build_object('product_ids',jsonb_build_array(p)))::text,'utf8'),'base64'));
 if jsonb_array_length(ctx->'products'->0->'variations')<>1 then raise exception 'Writer context missing active variants'; end if;
 if public.olivia_catalog_product_context(p,false) ? 'variations' then raise exception 'Router context unnecessarily expanded'; end if;
 if has_function_privilege('anon','public.sync_catalog_variations(jsonb)','execute') or has_table_privilege('authenticated','public.catalog_variations','select') then raise exception 'Variants publicly exposed'; end if;
end;$$;
select 'PASS: atomic complete snapshots, retries, stale protection, zero/null inventory, retirement, preserved notes, writer variant context and private access.' as result;
rollback;
