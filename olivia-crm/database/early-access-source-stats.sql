create or replace function public.olivia_early_access_source_stats()
returns jsonb language sql stable set search_path = '' as $$
  with enrolled as (
    select id from public.contacts
    where 'bf2026_early_access' = any(manual_tags) and coalesce(source, '') <> 'qa_test'
  ), forms as (
    select e.contact_id,
      bool_or(e.source = 'meta_lead_form') as meta,
      bool_or(e.source = 'landing_form') as web
    from public.contact_events e join enrolled c on c.id = e.contact_id
    where e.event_type = 'early_access_registered' and e.source in ('meta_lead_form', 'landing_form')
    group by e.contact_id
  )
  select jsonb_build_object(
    'meta_form', count(*) filter (where coalesce(f.meta, false)),
    'web_form', count(*) filter (where coalesce(f.web, false)),
    'both_forms', count(*) filter (where coalesce(f.meta, false) and coalesce(f.web, false)),
    'other_or_unknown', count(*) filter (where f.contact_id is null)
  ) from enrolled c left join forms f on f.contact_id = c.id;
$$;
revoke all on function public.olivia_early_access_source_stats() from public, anon, authenticated;
grant execute on function public.olivia_early_access_source_stats() to service_role;
