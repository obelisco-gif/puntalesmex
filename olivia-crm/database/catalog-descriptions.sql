alter table public.catalog_products add column if not exists description text;
CREATE OR REPLACE FUNCTION public.olivia_catalog_product_context(p_id uuid, p_detailed boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select jsonb_build_object('id',p.id,'name',p.name,'url',p.permalink,'price',p.price,'currency',p.currency,'stock_status',p.stock_status,'stock_quantity',p.stock_quantity,'synced_at',p.synced_at,'product_type',p.product_type,'attributes',p.attributes,'variations_synced_at',p.variations_synced_at,'variations_sync_status',p.variations_sync_status,
 'variation_count',(select count(*) from public.catalog_variations v where v.catalog_product_id=p.id and v.is_active and v.status='publish' and p.product_type='variable'))
 ||case when p_detailed then jsonb_build_object('short_description',p.short_description,'description',p.description,'description_source','woocommerce','variations',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'woocommerce_variation_id',v.woocommerce_variation_id,'name',v.name,'sku',v.sku,'attributes',v.attributes,'price',v.price,'regular_price',v.regular_price,'sale_price',v.sale_price,'on_sale',v.on_sale,'purchasable',v.purchasable,'stock_status',v.stock_status,'stock_quantity',v.stock_quantity,'url',v.permalink,'synced_at',v.synced_at) order by v.woocommerce_variation_id) from public.catalog_variations v where v.catalog_product_id=p.id and v.is_active and v.status='publish' and p.product_type='variable'),'[]')) else '{}'::jsonb end
 from public.catalog_products p where p.id=p_id;
$function$;
create or replace function public.olivia_sync_catalog_parent(p_payload jsonb) returns table(catalog_product_id uuid,woocommerce_product_id bigint,product_type text,expected_ids jsonb,requested_at timestamptz) language plpgsql set search_path='' as $f$
declare pid uuid;begin
pid:=public.sync_catalog_product(p_payload);
update public.catalog_products p set description=case when p_payload ? 'description' then nullif(p_payload->>'description','') else p.description end, variations_sync_status=case when p.product_type='variable' then 'pending' else 'not_applicable' end where p.id=pid;
return query select pid,(p_payload->>'woocommerce_product_id')::bigint,p_payload->>'product_type',coalesce(p_payload->'expected_variation_ids','[]'::jsonb),clock_timestamp();end;$f$;
