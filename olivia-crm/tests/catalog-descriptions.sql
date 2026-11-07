begin;do $t$ declare id1 uuid;x jsonb;begin
insert into public.catalog_products(woocommerce_product_id,name,status,short_description,description) values(959591,'Mg4 QA','publish','Contiene bisglicinato, citrato, malato y taurato','Ficha completa de prueba') returning id into id1;
x:=public.olivia_catalog_product_context(id1,true);if x->>'short_description' not like '%bisglicinato%' or x->>'description'<>'Ficha completa de prueba' or x->>'description_source'<>'woocommerce' then raise exception 'Description absent from selected product';end if;
x:=public.olivia_catalog_product_context(id1,false);if x?'description' or x?'short_description' then raise exception 'Description unnecessarily included in whole catalogue';end if;
end;$t$;rollback;select 'PASS: selected product includes WooCommerce descriptions, compact index excludes them' as result;
