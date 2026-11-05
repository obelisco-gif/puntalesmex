-- Separate statements avoid updating a row twice in the same SQL command.
create or replace function public.olivia_sync_catalog_parent(p_payload jsonb)
returns table(catalog_product_id uuid,woocommerce_product_id bigint,product_type text,expected_ids jsonb,requested_at timestamptz)
language plpgsql set search_path='' as $$
declare pid uuid;
begin
 pid:=public.sync_catalog_product(p_payload);
 update public.catalog_products p set variations_sync_status=case when p.product_type='variable' then 'pending' else 'not_applicable' end where p.id=pid;
 return query select pid,(p_payload->>'woocommerce_product_id')::bigint,p_payload->>'product_type',coalesce(p_payload->'expected_variation_ids','[]'::jsonb),clock_timestamp();
end;$$;
revoke all on function public.olivia_sync_catalog_parent(jsonb),public.sync_catalog_product(jsonb) from public,anon,authenticated;
grant execute on function public.olivia_sync_catalog_parent(jsonb),public.sync_catalog_product(jsonb) to service_role;
