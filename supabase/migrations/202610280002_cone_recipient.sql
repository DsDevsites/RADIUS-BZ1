-- RADIUS BZ1: registra quem recebeu o cone separadamente de quem liberou.
alter table public.cones add column if not exists active_holder_name text;
alter table public.movements add column if not exists recipient_name text;

drop function if exists public.move_cone(uuid,text,text,text);
create function public.move_cone(
  p_cone_id uuid,
  p_action text,
  p_area text default null,
  p_notes text default null,
  p_holder_name text default null
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_cone public.cones%rowtype;
  v_uid uuid := (select auth.uid());
  v_status text;
  v_area text;
begin
  if v_uid is null then raise exception 'É necessário entrar no sistema.'; end if;
  if p_action not in ('retirada','devolucao','manutencao') then raise exception 'Ação inválida.'; end if;
  select * into v_cone from public.cones where id=p_cone_id for update;
  if not found then raise exception 'Cone não encontrado.'; end if;
  v_status:=v_cone.status; v_area:=v_cone.area;

  if p_action='retirada' then
    if v_cone.status<>'almoxarifado' then raise exception 'Cone não está disponível no almoxarifado.'; end if;
    if nullif(trim(p_area),'') is null then raise exception 'Informe a área de destino.'; end if;
    if nullif(trim(p_holder_name),'') is null then raise exception 'Informe o nome de quem recebeu o cone.'; end if;
    update public.cones
      set status='operacional', area=trim(p_area), active_holder_id=v_uid,
          active_holder_name=trim(p_holder_name), updated_at=now()
      where id=p_cone_id;
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes,recipient_name)
      values(p_cone_id,v_uid,p_action,v_status,'operacional',v_area,trim(p_area),p_notes,trim(p_holder_name));
  elsif p_action='devolucao' then
    if v_cone.status<>'operacional' then raise exception 'Cone não está em área operacional.'; end if;
    if v_cone.active_holder_id is distinct from v_uid and not public.is_radius_admin() then
      raise exception 'Somente quem liberou o cone ou o administrador pode registrar a devolução.';
    end if;
    update public.cones
      set status='almoxarifado', area=null, active_holder_id=null,
          active_holder_name=null, updated_at=now()
      where id=p_cone_id;
    update public.movements set returned_at=now()
      where cone_id=p_cone_id and returned_at is null and action='retirada';
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes,recipient_name)
      values(p_cone_id,v_uid,p_action,v_status,'almoxarifado',v_area,null,p_notes,v_cone.active_holder_name);
  else
    if not public.is_radius_admin() then raise exception 'Somente administrador pode enviar para manutenção.'; end if;
    update public.cones set status='manutencao', updated_at=now() where id=p_cone_id;
    insert into public.movements(cone_id,user_id,action,from_status,to_status,from_area,to_area,notes)
      values(p_cone_id,v_uid,p_action,v_status,'manutencao',v_area,v_area,p_notes);
  end if;
end;
$$;
revoke all on function public.move_cone(uuid,text,text,text,text) from public;
grant execute on function public.move_cone(uuid,text,text,text,text) to authenticated;
