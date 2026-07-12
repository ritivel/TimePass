-- Keep temporary accounts and low-value telemetry bounded without requiring
-- an external worker. Deleting an auth user cascades to their conversations,
-- events and guest-usage row through the existing foreign keys.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule(
  'nakul-delete-stale-anonymous-users',
  '17 3 * * *',
  $$
    delete from auth.users
     where is_anonymous is true
       and created_at < now() - interval '30 days';
  $$
);

select cron.schedule(
  'nakul-delete-old-product-events',
  '41 3 * * *',
  $$
    delete from public.product_events
     where created_at < now() - interval '90 days';
  $$
);

-- pg_cron does not prune its own run history. Keep enough for debugging while
-- preventing the monitoring table from growing without bound.
select cron.schedule(
  'nakul-delete-old-cron-run-details',
  '8 4 * * 0',
  $$
    delete from cron.job_run_details
     where end_time < now() - interval '30 days';
  $$
);
