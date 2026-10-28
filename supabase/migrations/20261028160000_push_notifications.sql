create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon;
grant select, insert, update, delete on public.push_subscriptions to authenticated;
drop policy if exists "Users manage their own push subscriptions" on public.push_subscriptions;
create policy "Users manage their own push subscriptions"
  on public.push_subscriptions for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create table if not exists public.push_notification_log (
  id bigint generated always as identity primary key,
  subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
  cone_id uuid not null references public.cones(id) on delete cascade,
  due_date date not null,
  notification_kind text not null check (notification_kind in ('tomorrow', 'today', 'expired')),
  sent_at timestamptz not null default now(),
  unique (subscription_id, cone_id, due_date, notification_kind)
);
alter table public.push_notification_log enable row level security;
revoke all on public.push_notification_log from anon, authenticated;
grant all on public.push_notification_log to service_role;
