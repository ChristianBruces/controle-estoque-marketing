-- ATEM | Controle de Estoque Marketing e Comercial
-- Execute este arquivo no Supabase em: SQL Editor > New query > Run.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type app_role as enum ('assistant', 'analyst', 'manager');
  end if;

  if not exists (select 1 from pg_type where typname = 'movement_type') then
    create type movement_type as enum ('entry', 'exit', 'adjust', 'transfer');
  end if;

  if not exists (select 1 from pg_type where typname = 'movement_status') then
    create type movement_status as enum ('effective', 'pending', 'approved', 'rejected');
  end if;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role app_role not null default 'assistant',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category_id uuid references public.categories(id),
  department_id uuid references public.departments(id),
  campaign_id uuid references public.campaigns(id),
  supplier_id uuid references public.suppliers(id),
  minimum_critical integer not null default 0 check (minimum_critical >= 0),
  attention_limit integer not null default 0 check (attention_limit >= 0),
  unit text not null default 'un.',
  location text,
  description text,
  observations text,
  photo_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (attention_limit >= minimum_critical)
);

create table if not exists public.movements (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  type movement_type not null,
  quantity integer not null default 0,
  status movement_status not null default 'effective',
  detail text,
  requester text,
  campaign_id uuid references public.campaigns(id),
  from_department_id uuid references public.departments(id),
  to_department_id uuid references public.departments(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  balance_after integer,
  check (
    (type in ('entry', 'exit') and quantity > 0)
    or (type = 'adjust' and quantity <> 0)
    or (type = 'transfer' and quantity = 0)
  )
);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists items_touch_updated_at on public.items;
create trigger items_touch_updated_at
before update on public.items
for each row execute function public.touch_updated_at();

create or replace function public.app_current_role()
returns app_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.app_is_at_least(required_role app_role)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_role app_role;
begin
  current_role := public.app_current_role();

  if current_role is null then
    return false;
  end if;

  return case required_role
    when 'assistant' then current_role in ('assistant', 'analyst', 'manager')
    when 'analyst' then current_role in ('analyst', 'manager')
    when 'manager' then current_role = 'manager'
  end;
end;
$$;

create or replace function public.app_get_or_create_department(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
begin
  if nullif(trim(p_name), '') is null then
    return null;
  end if;

  insert into public.departments(name)
  values (trim(p_name))
  on conflict (name) do update set active = true
  returning id into result_id;

  return result_id;
end;
$$;

create or replace function public.app_get_or_create_category(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
begin
  if nullif(trim(p_name), '') is null then
    return null;
  end if;

  insert into public.categories(name)
  values (trim(p_name))
  on conflict (name) do update set active = true
  returning id into result_id;

  return result_id;
end;
$$;

create or replace function public.app_get_or_create_campaign(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
begin
  if nullif(trim(p_name), '') is null then
    return null;
  end if;

  insert into public.campaigns(name)
  values (trim(p_name))
  on conflict (name) do update set active = true
  returning id into result_id;

  return result_id;
end;
$$;

create or replace function public.app_get_or_create_supplier(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  result_id uuid;
begin
  if nullif(trim(p_name), '') is null then
    return null;
  end if;

  insert into public.suppliers(name)
  values (trim(p_name))
  on conflict (name) do update set active = true
  returning id into result_id;

  return result_id;
end;
$$;

create or replace view public.inventory_items as
select
  i.id,
  i.code,
  i.name,
  c.name as category,
  d.name as area,
  ca.name as campaign,
  s.name as supplier,
  coalesce(sum(
    case
      when m.status in ('effective', 'approved') and m.type = 'entry' then m.quantity
      when m.status in ('effective', 'approved') and m.type = 'exit' then -m.quantity
      when m.status = 'approved' and m.type = 'adjust' then m.quantity
      else 0
    end
  ), 0)::integer as stock,
  i.minimum_critical,
  i.attention_limit,
  i.unit,
  i.location,
  i.description,
  i.observations,
  i.photo_url,
  '●' as icon,
  i.created_at,
  i.updated_at
from public.items i
left join public.categories c on c.id = i.category_id
left join public.departments d on d.id = i.department_id
left join public.campaigns ca on ca.id = i.campaign_id
left join public.suppliers s on s.id = i.supplier_id
left join public.movements m on m.item_id = i.id
group by i.id, c.name, d.name, ca.name, s.name;

create or replace view public.inventory_movements as
select
  m.id,
  m.item_id,
  m.type::text as type,
  case
    when m.type = 'exit' then -m.quantity
    else m.quantity
  end as quantity,
  m.status::text as status,
  m.detail,
  m.requester,
  m.created_at,
  p.full_name as user_name,
  ap.full_name as approved_by_name,
  m.approved_at,
  m.balance_after
from public.movements m
left join public.profiles p on p.id = m.created_by
left join public.profiles ap on ap.id = m.approved_by;

create or replace function public.app_item_balance(p_item_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(
    case
      when status in ('effective', 'approved') and type = 'entry' then quantity
      when status in ('effective', 'approved') and type = 'exit' then -quantity
      when status = 'approved' and type = 'adjust' then quantity
      else 0
    end
  ), 0)::integer
  from public.movements
  where item_id = p_item_id
$$;

create or replace function public.app_create_item(
  p_code text,
  p_name text,
  p_category_name text,
  p_department_name text,
  p_campaign_name text,
  p_supplier_name text,
  p_initial_stock integer,
  p_minimum_critical integer,
  p_attention_limit integer,
  p_unit text,
  p_location text,
  p_description text,
  p_observations text,
  p_photo_url text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_item_id uuid;
begin
  if not public.app_is_at_least('analyst') then
    raise exception 'Perfil sem permissão para cadastrar materiais.';
  end if;

  insert into public.items (
    code, name, category_id, department_id, campaign_id, supplier_id,
    minimum_critical, attention_limit, unit, location, description, observations,
    photo_url, created_by
  )
  values (
    upper(trim(p_code)), trim(p_name),
    public.app_get_or_create_category(p_category_name),
    public.app_get_or_create_department(p_department_name),
    public.app_get_or_create_campaign(p_campaign_name),
    public.app_get_or_create_supplier(p_supplier_name),
    greatest(coalesce(p_minimum_critical, 0), 0),
    greatest(coalesce(p_attention_limit, 0), 0),
    coalesce(nullif(trim(p_unit), ''), 'un.'),
    nullif(trim(p_location), ''),
    nullif(trim(p_description), ''),
    nullif(trim(p_observations), ''),
    nullif(trim(p_photo_url), ''),
    auth.uid()
  )
  returning id into new_item_id;

  if coalesce(p_initial_stock, 0) > 0 then
    insert into public.movements(item_id, type, quantity, status, detail, created_by, balance_after)
    values (new_item_id, 'entry', p_initial_stock, 'effective', 'Saldo inicial do cadastro', auth.uid(), p_initial_stock);
  end if;

  return new_item_id;
end;
$$;

create or replace function public.app_update_item(
  p_item_id uuid,
  p_code text,
  p_name text,
  p_category_name text,
  p_department_name text,
  p_campaign_name text,
  p_supplier_name text,
  p_minimum_critical integer,
  p_attention_limit integer,
  p_unit text,
  p_location text,
  p_description text,
  p_observations text,
  p_photo_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.app_is_at_least('analyst') then
    raise exception 'Perfil sem permissão para editar materiais.';
  end if;

  update public.items
  set
    code = upper(trim(p_code)),
    name = trim(p_name),
    category_id = public.app_get_or_create_category(p_category_name),
    department_id = public.app_get_or_create_department(p_department_name),
    campaign_id = public.app_get_or_create_campaign(p_campaign_name),
    supplier_id = public.app_get_or_create_supplier(p_supplier_name),
    minimum_critical = greatest(coalesce(p_minimum_critical, 0), 0),
    attention_limit = greatest(coalesce(p_attention_limit, 0), 0),
    unit = coalesce(nullif(trim(p_unit), ''), 'un.'),
    location = nullif(trim(p_location), ''),
    description = nullif(trim(p_description), ''),
    observations = nullif(trim(p_observations), ''),
    photo_url = nullif(trim(p_photo_url), '')
  where id = p_item_id;
end;
$$;

create or replace function public.app_register_movement(
  p_type movement_type,
  p_item_id uuid,
  p_quantity integer,
  p_detail text,
  p_requester text,
  p_campaign_name text,
  p_new_department_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_balance integer;
  new_balance integer;
  new_id uuid;
  current_department uuid;
  new_department uuid;
begin
  if not public.app_is_at_least('assistant') then
    raise exception 'Usuário sem perfil cadastrado.';
  end if;

  select public.app_item_balance(p_item_id), department_id
  into current_balance, current_department
  from public.items
  where id = p_item_id
  for update;

  if current_balance is null then
    raise exception 'Material não encontrado.';
  end if;

  if p_type in ('entry', 'exit') and coalesce(p_quantity, 0) <= 0 then
    raise exception 'Informe uma quantidade maior que zero.';
  end if;

  if p_type = 'exit' and p_quantity > current_balance then
    raise exception 'Saldo insuficiente para esta saída.';
  end if;

  if p_type = 'transfer' then
    new_department := public.app_get_or_create_department(p_new_department_name);
    if new_department is null or new_department = current_department then
      raise exception 'Selecione uma nova área responsável.';
    end if;

    update public.items set department_id = new_department where id = p_item_id;
    insert into public.movements(item_id, type, quantity, status, detail, requester, from_department_id, to_department_id, created_by, balance_after)
    values (p_item_id, 'transfer', 0, 'effective', p_detail, p_requester, current_department, new_department, auth.uid(), current_balance)
    returning id into new_id;

    return new_id;
  end if;

  if p_type = 'adjust' then
    insert into public.movements(item_id, type, quantity, status, detail, requester, campaign_id, created_by, balance_after)
    values (p_item_id, 'adjust', p_quantity, 'pending', p_detail, p_requester, public.app_get_or_create_campaign(p_campaign_name), auth.uid(), current_balance)
    returning id into new_id;

    return new_id;
  end if;

  new_balance := current_balance + case when p_type = 'entry' then p_quantity else -p_quantity end;

  insert into public.movements(item_id, type, quantity, status, detail, requester, campaign_id, created_by, balance_after)
  values (p_item_id, p_type, p_quantity, 'effective', p_detail, p_requester, public.app_get_or_create_campaign(p_campaign_name), auth.uid(), new_balance)
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.app_approve_movement(p_movement_id uuid, p_approved boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.movements;
  current_balance integer;
  new_balance integer;
begin
  if not public.app_is_at_least('manager') then
    raise exception 'Apenas gestores podem aprovar ou recusar ajustes.';
  end if;

  select * into target
  from public.movements
  where id = p_movement_id
  for update;

  if target.id is null or target.type <> 'adjust' or target.status <> 'pending' then
    raise exception 'Ajuste pendente não encontrado.';
  end if;

  current_balance := public.app_item_balance(target.item_id);

  if p_approved then
    new_balance := current_balance + target.quantity;

    if new_balance < 0 then
      raise exception 'A aprovação deixaria o saldo negativo.';
    end if;

    update public.movements
    set status = 'approved', approved_by = auth.uid(), approved_at = now(), balance_after = new_balance
    where id = p_movement_id;
  else
    update public.movements
    set status = 'rejected', approved_by = auth.uid(), approved_at = now(), balance_after = current_balance
    where id = p_movement_id;
  end if;
end;
$$;

insert into public.departments(name) values ('Marketing'), ('Comercial')
on conflict (name) do nothing;

insert into public.categories(name) values ('Brindes'), ('Materiais Gráficos'), ('Enxovais'), ('Eventos')
on conflict (name) do nothing;

insert into public.campaigns(name) values ('Acelera Aí'), ('Combustível do Bem'), ('Inauguração de posto')
on conflict (name) do nothing;

alter table public.profiles enable row level security;
alter table public.departments enable row level security;
alter table public.categories enable row level security;
alter table public.campaigns enable row level security;
alter table public.suppliers enable row level security;
alter table public.items enable row level security;
alter table public.movements enable row level security;

drop policy if exists "profiles_select_own_or_manager" on public.profiles;
create policy "profiles_select_own_or_manager"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.app_is_at_least('manager'));

drop policy if exists "profiles_manager_manage" on public.profiles;
create policy "profiles_manager_manage"
on public.profiles for all
to authenticated
using (public.app_is_at_least('manager'))
with check (public.app_is_at_least('manager'));

drop policy if exists "departments_select" on public.departments;
create policy "departments_select" on public.departments for select to authenticated using (true);

drop policy if exists "categories_select" on public.categories;
create policy "categories_select" on public.categories for select to authenticated using (true);

drop policy if exists "campaigns_select" on public.campaigns;
create policy "campaigns_select" on public.campaigns for select to authenticated using (true);

drop policy if exists "suppliers_select" on public.suppliers;
create policy "suppliers_select" on public.suppliers for select to authenticated using (true);

drop policy if exists "items_select" on public.items;
create policy "items_select" on public.items for select to authenticated using (true);

drop policy if exists "movements_select" on public.movements;
create policy "movements_select" on public.movements for select to authenticated using (true);

grant usage on schema public to authenticated;
grant select on public.inventory_items to authenticated;
grant select on public.inventory_movements to authenticated;
grant select on public.profiles, public.departments, public.categories, public.campaigns, public.suppliers, public.items, public.movements to authenticated;
grant execute on function public.app_create_item(text,text,text,text,text,text,integer,integer,integer,text,text,text,text,text) to authenticated;
grant execute on function public.app_update_item(uuid,text,text,text,text,text,text,integer,integer,text,text,text,text,text) to authenticated;
grant execute on function public.app_register_movement(movement_type,uuid,integer,text,text,text,text) to authenticated;
grant execute on function public.app_approve_movement(uuid,boolean) to authenticated;
