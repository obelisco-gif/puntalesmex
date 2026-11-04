begin;
do $$
declare a uuid; b uuid; later_id uuid; r jsonb; history jsonb; base jsonb;
begin
 insert into public.contacts(email,phone,first_name) values('buyer@example.invalid','34999000301','Nombre confirmado') returning id into a;
 insert into public.contacts(phone) values('+34999000200') returning id into b;
 base:='{"id":1,"order_number":"WC-1","status":"completed","billing_email":"BUYER@example.invalid","billing_phone":"999000301","billing_country":"ES","billing_first_name":"Nombre antiguo","currency":"EUR","total":42.50,"refunded_total":0,"created_at_woo":"2026-10-01T10:00:00Z","paid_at":"2026-10-01T10:01:00Z","source_modified_at":"2026-11-04T09:00:00Z","items":[{"line_id":1,"product_id":10,"name":"Colágeno","quantity":1,"total":42.50}]}'::jsonb;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base));
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base));
 if (select count(*) from public.woo_orders where contact_id=a)<>1 or (select count(*) from public.woo_order_items where order_id=1)<>1 then raise exception 'order retry duplicated'; end if;
 if (select first_name from public.contacts where id=a)<>'Nombre confirmado' or (select stage from public.contacts where id=a)<>'customer' then raise exception 'name/customer state failed'; end if;
 history:=public.olivia_purchase_history(a);
 if history->>'purchase_count'<>'1' or jsonb_array_length(history->'usual_products')<>0 then raise exception 'one purchase invented a habit'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"id":2,"order_number":"WC-2","created_at_woo":"2026-11-01T10:00:00Z","paid_at":"2026-11-01T10:01:00Z"}'::jsonb));
 history:=public.olivia_purchase_history(a);
 if history->>'purchase_count'<>'2' or history#>>'{usual_products,0,orders}'<>'2' or history->>'last_purchase_at'<>'2026-11-01T10:01:00+00:00' then raise exception 'last purchase/habits failed'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"id":3,"order_number":"WC-3","status":"cancelled","created_at_woo":"2026-11-03T10:00:00Z","paid_at":null}'::jsonb));
 if public.olivia_purchase_history(a)->>'purchase_count'<>'2' then raise exception 'cancelled order counted as purchase'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"id":4,"billing_email":null,"billing_phone":"+34999000200","billing_country":null}'::jsonb));
 if (select contact_id from public.woo_orders where id=4) is distinct from b then raise exception 'phone-only match failed'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"id":5,"billing_phone":"+34999000200"}'::jsonb));
 if (select match_status from public.woo_orders where id=5)<>'ambiguous' or (select contact_id from public.woo_orders where id=5) is not null then raise exception 'conflicting identities linked'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"id":6,"billing_email":"later@example.invalid","billing_phone":null}'::jsonb));
 insert into public.contacts(email) values('later@example.invalid') returning id into later_id;
 if (select contact_id from public.woo_orders where id=6) is distinct from later_id then raise exception 'cached history not relinked to new contact'; end if;
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base||'{"status":"refunded","refunded_total":42.50,"source_modified_at":"2026-11-04T10:00:00Z"}'::jsonb));
 perform public.olivia_ingest_woo_orders(jsonb_build_array(base));
 if (select status from public.woo_orders where id=1)<>'refunded' or public.olivia_purchase_history(a)->>'purchase_count'<>'1' then raise exception 'refund/older snapshot failed'; end if;
 if exists(select 1 from public.contact_channel_consents where contact_id in (a,b,later_id)) then raise exception 'orders granted marketing consent'; end if;
 perform public.olivia_complete_woo_sync(now());
 if public.olivia_purchase_history(a)->>'history_complete'<>'true' then raise exception 'history completeness not recorded'; end if;
 if has_table_privilege('anon','public.woo_orders','select') then raise exception 'orders exposed'; end if;
end;$$;
select 'PASS: order identity matching, ambiguity, latest purchase, repeat products, refunds, cancellations, retries and unchanged permissions' as result;
rollback;

