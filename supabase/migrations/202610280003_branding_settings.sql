create table if not exists public.app_settings (
 id integer primary key default 1 check (id=1),
 system_name text not null default 'RADIUS BZ1',
 logo_url text,
 updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
insert into public.app_settings(id,system_name) values(1,'RADIUS BZ1') on conflict(id) do nothing;
drop policy if exists "authenticated read app settings" on public.app_settings;
create policy "authenticated read app settings" on public.app_settings for select to authenticated using(true);
drop policy if exists "admin insert app settings" on public.app_settings;
create policy "admin insert app settings" on public.app_settings for insert to authenticated with check(public.is_radius_admin());
drop policy if exists "admin update app settings" on public.app_settings;
create policy "admin update app settings" on public.app_settings for update to authenticated using(public.is_radius_admin()) with check(public.is_radius_admin());
grant select, insert, update on public.app_settings to authenticated;
