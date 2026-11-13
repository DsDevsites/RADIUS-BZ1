-- RADIUS BZ1: histórico de atualizações e validade automática, sem alterar dados existentes.
alter table public.cones
  add column if not exists last_updated_date date;

create table if not exists public.cone_update_history (
  id uuid primary key default gen_random_uuid(),
  cone_id uuid not null references public.cones(id) on delete restrict,
  update_date date not null,
  previous_due_date date,
  new_due_date date not null,
  user_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists cone_update_history_cone_created_idx
  on public.cone_update_history (cone_id, created_at desc);

alter table public.cone_update_history enable row level security;

drop policy if exists "admin read cone update history" on public.cone_update_history;
create policy "admin read cone update history"
  on public.cone_update_history for select to authenticated
  using (public.is_radius_admin());

drop policy if exists "admin insert cone update history" on public.cone_update_history;
create policy "admin insert cone update history"
  on public.cone_update_history for insert to authenticated
  with check (public.is_radius_admin() and user_id = (select auth.uid()));

grant select, insert on table public.cone_update_history to authenticated;

create or replace function public.update_cone_validity(
  p_cone_id uuid,
  p_update_date date
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_previous_due date;
  v_new_due date;
begin
  if v_uid is null then
    raise exception 'É necessário entrar no sistema.';
  end if;
  if not public.is_radius_admin() then
    raise exception 'Somente o administrador pode atualizar a validade dos cones.';
  end if;
  if p_update_date is null then
    raise exception 'Informe a data da atualização.';
  end if;
  if p_update_date > current_date then
    raise exception 'A data da atualização não pode estar no futuro.';
  end if;

  select due_date
    into v_previous_due
    from public.cones
   where id = p_cone_id
   for update;

  if not found then
    raise exception 'Cone não encontrado.';
  end if;

  v_new_due := p_update_date + 15;

  insert into public.cone_update_history (
    cone_id, update_date, previous_due_date, new_due_date, user_id
  ) values (
    p_cone_id, p_update_date, v_previous_due, v_new_due, v_uid
  );

  update public.cones
     set last_updated_date = p_update_date,
         due_date = v_new_due,
         updated_at = now()
   where id = p_cone_id;
end;
$$;

revoke all on function public.update_cone_validity(uuid, date) from public;
revoke execute on function public.update_cone_validity(uuid, date) from anon;
grant execute on function public.update_cone_validity(uuid, date) to authenticated;
