-- RADIUS BZ1: schema inicial. Execute no SQL Editor do projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Usuário',
  email text,
  employee_code text,
  role text not null default 'user' check (role in ('admin','user')),
  created_at timestamptz not null default now()
);

create table if not exists public.cones (
  id uuid primary key default gen_random_uuid(),
  tag text not null unique,
  name text not null,
  description text,
  photo_url text,
  status text not null default 'almoxarifado' check (status in ('almoxarifado','operacional','manutencao')),
  area text,
  due_date date,
  active_holder_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.movements (
  id uuid primary key default gen_random_uuid(),
  cone_id uuid not null references public.cones(id),
  user_id uuid not null references public.profiles(id),
  action text not null check (action in ('retirada','devolucao','transferencia','manutencao')),
  from_status text,
  to_status text,
  from_area text,
  to_area text,
  notes text,
  created_at timestamptz not null default now(),
  returned_at timestamptz
);
create index if not exists movements_cone_created_idx on public.movements(cone_id,created_at desc);
create index if not exists cones_due_date_idx on public.cones(due_date);
create index if not exists cones_status_idx on public.cones(status);

create table if not exists public.alert_settings (
  id integer primary key default 1 check (id=1),
  days_before integer not null default 3 check(days_before between 0 and 30),
  updated_at timestamptz not null default now()
);
insert into public.alert_settings(id,days_before) values(1,3) on conflict(id) do nothing;

create table if not exists public.alert_log (
  id uuid primary key default gen_random_uuid(),
  cone_id uuid not null references public.cones(id),
  due_date date not null,
  alert_type text not null check(alert_type in ('upcoming','expired')),
  sent_at timestamptz not null default now(),
  channel text not null default 'dashboard',
  status text not null default 'open' check(status in ('open','resolved','sent','failed')),
  unique(cone_id,due_date,alert_type,channel)
);

alter table public.profiles enable row level security;
alter table public.cones enable row level security;
alter table public.movements enable row level security;
alter table public.alert_settings enable row level security;
alter table public.alert_log enable row level security;

create or replace function public.is_radius_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin');
$$;
revoke all on function public.is_radius_admin() from public;
grant execute on function public.is_radius_admin() to authenticated;

drop policy if exists "profile read self or admin" on public.profiles;
create policy "profile read self or admin" on public.profiles for select to authenticated
using (id=(select auth.uid()) or public.is_radius_admin());
drop policy if exists "profile update self or admin" on public.profiles;
create policy "profile update self or admin" on public.profiles for update to authenticated
using (id=(select auth.uid()) or public.is_radius_admin())
with check (id=(select auth.uid()) or public.is_radius_admin());
drop policy if exists "profile insert self" on public.profiles;
create policy "profile insert self" on public.profiles for insert to authenticated
with check (id=(select auth.uid()) and role='user');

drop policy if exists "authenticated read cones" on public.cones;
create policy "authenticated read cones" on public.cones for select to authenticated using (true);
drop policy if exists "admin insert cones" on public.cones;
create policy "admin insert cones" on public.cones for insert to authenticated with check (public.is_radius_admin());
drop policy if exists "admin update cones" on public.cones;
create policy "admin update cones" on public.cones for update to authenticated using (public.is_radius_admin()) with check (public.is_radius_admin());
drop policy if exists "admin delete cones" on public.cones;
create policy "admin delete cones" on public.cones for delete to authenticated using (public.is_radius_admin());

drop policy if exists "authenticated read movements" on public.movements;
create policy "authenticated read movements" on public.movements for select to authenticated using (user_id=(select auth.uid()) or public.is_radius_admin());
drop policy if exists "authenticated insert own movement" on public.movements;
create policy "authenticated insert own movement" on public.movements for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "admin read alert settings" on public.alert_settings;
create policy "admin read alert settings" on public.alert_settings for select to authenticated using (public.is_radius_admin());
drop policy if exists "admin update alert settings" on public.alert_settings;
create policy "admin update alert settings" on public.alert_settings for update to authenticated using (public.is_radius_admin()) with check (public.is_radius_admin());
drop policy if exists "authenticated read alerts" on public.alert_log;
create policy "authenticated read alerts" on public.alert_log for select to authenticated using (public.is_radius_admin());

-- O usuário autenticado só pode movimentar cones. A função valida ações e atualiza
-- cone + histórico em uma transação para evitar duas retiradas concorrentes.
create or replace function public.move_cone(p_cone_id uuid, p_action text, p_area text default null, p_notes text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_cone public.cones%rowtype;
  v_uid uuid := (select auth.uid());
  v_status text;
  v_area text;
  v_holder uuid;
begin
  if v_uid is null then raise exception 'É necessário entrar no sistema.'; end if;
  if p_action not in ('retirada','devolucao','manutencao') then raise exception 'Ação inválida.'; end if;
  select * into v_cone from public.cones where id=p_cone_id for update;
  if not found then raise exception 'Cone não encontrado.'; end if;
  v_status := v_cone.status; v_area := v_cone.area; v_holder := v_cone.active_holder_id;
  if p_action='retirada' then
    if v_cone.status <> 'almoxarifado' then raise exception 'Cone não está disponível no almoxarifado.'; end if;
    if nullif(trim(p_area),'') is null then raise exception 'Informe a área de destino.'; end if;
    update public.cones set status='operacional', area=trim(p_area), active_holder_id=v_uid, updated_at=now() where id=p_cone_id;
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes) values(p_cone_id,v_uid,p_action,v_status,'operacional',v_area,trim(p_area),p_notes);
  elsif p_action='devolucao' then
    if v_cone.status <> 'operacional' then raise exception 'Cone não está em área operacional.'; end if;
    if v_cone.active_holder_id <> v_uid and not public.is_radius_admin() then raise exception 'Somente o responsável atual ou o administrador pode devolver este cone.'; end if;
    update public.cones set status='almoxarifado', area=null, active_holder_id=null, updated_at=now() where id=p_cone_id;
    update public.movements set returned_at=now() where cone_id=p_cone_id and returned_at is null and action='retirada';
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes) values(p_cone_id,v_uid,p_action,v_status,'almoxarifado',v_area,null,p_notes);
  else
    if not public.is_radius_admin() then raise exception 'Somente o administrador pode enviar cone para manutenção.'; end if;
    update public.cones set status='manutencao', updated_at=now() where id=p_cone_id;
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes) values(p_cone_id,v_uid,p_action,v_status,'manutencao',v_area,v_area,p_notes);
  end if;
end;
$$;
revoke all on function public.move_cone(uuid,text,text,text) from public;
grant execute on function public.move_cone(uuid,text,text,text) to authenticated;

-- Cria perfil comum após cadastro. A elevação para administrador é manual e segura.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id,full_name,email,employee_code,role)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name','Usuário'), new.email, new.raw_user_meta_data->>'employee_code', 'user')
  on conflict(id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_radius on auth.users;
create trigger on_auth_user_created_radius after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Seed inicial: 8 registros aguardando TAG/nome/data reais. Altere os dados pelo painel admin.
insert into public.cones(tag,name,status) values
('RBZ1-001','Cone RADIUS BZ1 01','almoxarifado'),
('RBZ1-002','Cone RADIUS BZ1 02','almoxarifado'),
('RBZ1-003','Cone RADIUS BZ1 03','almoxarifado'),
('RBZ1-004','Cone RADIUS BZ1 04','almoxarifado'),
('RBZ1-005','Cone RADIUS BZ1 05','almoxarifado'),
('RBZ1-006','Cone RADIUS BZ1 06','almoxarifado'),
('RBZ1-007','Cone RADIUS BZ1 07','almoxarifado'),
('RBZ1-008','Cone RADIUS BZ1 08','almoxarifado')
on conflict(tag) do nothing;

-- Bucket de fotos: política de leitura pública para fotos não sigilosas e upload apenas admin.
insert into storage.buckets(id,name,public) values('cone-photos','cone-photos',true) on conflict(id) do nothing;
drop policy if exists "public read cone photos" on storage.objects;
create policy "public read cone photos" on storage.objects for select using(bucket_id='cone-photos');
drop policy if exists "admin upload cone photos" on storage.objects;
create policy "admin upload cone photos" on storage.objects for insert to authenticated with check(bucket_id='cone-photos' and public.is_radius_admin());
drop policy if exists "admin update cone photos" on storage.objects;
create policy "admin update cone photos" on storage.objects for update to authenticated using(bucket_id='cone-photos' and public.is_radius_admin()) with check(bucket_id='cone-photos' and public.is_radius_admin());
