-- Esquema PostgreSQL para implantação em nuvem (ex.: Supabase)
create type user_role as enum ('assistant','analyst','manager');
create type movement_type as enum ('entry','exit','adjustment','transfer');
create type approval_status as enum ('pending','approved','rejected');

create table departments (id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true, created_at timestamptz not null default now());
create table profiles (id uuid primary key references auth.users on delete cascade, full_name text not null, role user_role not null default 'assistant', created_at timestamptz not null default now());
create table categories (id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true);
create table campaigns (id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true);
create table suppliers (id uuid primary key default gen_random_uuid(), name text not null unique, contact text);
create table items (id uuid primary key default gen_random_uuid(), internal_code text not null unique, name text not null, category_id uuid references categories, department_id uuid not null references departments, campaign_id uuid references campaigns, unit text not null default 'un.', storage_location text, supplier_id uuid references suppliers, photo_path text, description text, notes text, minimum_quantity numeric not null default 0 check (minimum_quantity >= 0), attention_quantity numeric not null default 0 check (attention_quantity >= minimum_quantity), created_by uuid not null references profiles, created_at timestamptz not null default now());
create table movements (id uuid primary key default gen_random_uuid(), item_id uuid not null references items, type movement_type not null, quantity numeric not null, source_department_id uuid references departments, target_department_id uuid references departments, requester text, requesting_unit text, reason text, campaign_id uuid references campaigns, supplier_id uuid references suppliers, invoice_number text, notes text, occurred_at timestamptz not null default now(), created_by uuid not null references profiles, approval_status approval_status not null default 'approved', approved_by uuid references profiles, approved_at timestamptz, check ((type <> 'transfer') or (source_department_id is not null and target_department_id is not null)));

create view inventory_balance as select i.id, i.internal_code, i.name, i.department_id, coalesce(sum(case when m.type='entry' then m.quantity when m.type='exit' then -m.quantity when m.type='adjustment' then m.quantity else 0 end) filter (where m.approval_status='approved'),0) as available_quantity from items i left join movements m on m.item_id=i.id group by i.id;
insert into departments (name) values ('Marketing'),('Comercial');
