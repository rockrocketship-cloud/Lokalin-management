-- Slip gaji WA: penyesuaian gaji per periode + nomor WA staf (khusus Owner)
create table if not exists public.payroll_contacts (
  emp_id uuid primary key references public.employees(id) on delete cascade,
  no_wa text check (no_wa is null or no_wa ~ '^62[0-9]{8,13}$'),
  updated_at timestamptz not null default now()
);

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  periode text not null check (periode ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  emp_key text not null,
  rate integer check (rate is null or rate between 0 and 1000000000),
  meal integer not null default 0 check (meal between 0 and 1000000000),
  bonus integer not null default 0 check (bonus between 0 and 1000000000),
  deduct integer not null default 0 check (deduct between 0 and 1000000000),
  catatan text,
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (periode, emp_key)
);

alter table public.payroll_contacts enable row level security;
alter table public.payroll_adjustments enable row level security;

do $$
declare t text;
begin
  foreach t in array array['payroll_contacts','payroll_adjustments'] loop
    execute format($p$create policy %I on public.%I for all to authenticated
      using (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))
      with check (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))$p$,
      'lokalin_owner_all_' || t, t);
  end loop;
end $$;
