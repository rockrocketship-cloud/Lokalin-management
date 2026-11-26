-- Stok: supplier, target stok (daftar belanja), jenis Rusak, dan harga beli saat Masuk.
-- Diadaptasi dari konsep OpenSourcePOS (supplier, receiving), ERPNext (reorder level), dan URY (wastage).
-- Aditif: data lama tidak diubah.

create table if not exists public.lokalin_stock_suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) > 0),
  phone text,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.lokalin_stock_suppliers enable row level security;

drop policy if exists stock_suppliers_read on public.lokalin_stock_suppliers;
create policy stock_suppliers_read on public.lokalin_stock_suppliers
  for select to authenticated
  using ((select public.lokalin_stock_my_role()) is not null);

drop policy if exists stock_suppliers_write on public.lokalin_stock_suppliers;
create policy stock_suppliers_write on public.lokalin_stock_suppliers
  for all to authenticated
  using ((select public.lokalin_stock_my_role()) in ('owner', 'staff'))
  with check ((select public.lokalin_stock_my_role()) in ('owner', 'staff'));

alter table public.lokalin_stock_items
  add column if not exists supplier_id uuid references public.lokalin_stock_suppliers (id) on delete set null,
  add column if not exists target_stock numeric check (target_stock is null or target_stock >= 0);

create index if not exists lokalin_stock_items_supplier_idx on public.lokalin_stock_items (supplier_id);

alter table public.lokalin_stock_transactions
  add column if not exists unit_price numeric check (unit_price is null or unit_price >= 0);

create index if not exists lokalin_stock_transactions_item_created_idx
  on public.lokalin_stock_transactions (item_id, created_at desc);

alter table public.lokalin_stock_transactions
  drop constraint if exists lokalin_stock_transactions_transaction_type_check;
alter table public.lokalin_stock_transactions
  add constraint lokalin_stock_transactions_transaction_type_check
  check (transaction_type in ('Masuk', 'Keluar', 'Opname', 'Rusak'));

drop function if exists public.lokalin_stock_record(uuid, text, numeric, text);

create function public.lokalin_stock_record(
  p_item_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text default null,
  p_unit_price numeric default null
)
returns table (transaction_id uuid, stock_before numeric, stock_after numeric)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_division text;
  v_before numeric;
  v_after numeric;
  v_price numeric;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  select r.role into v_role from public.lokalin_stock_roles r where r.user_id = auth.uid();
  if v_role is null or v_role not in ('owner', 'staff', 'bar', 'kitchen') then
    raise exception 'Akses ditolak';
  end if;

  if p_type is null or p_type not in ('Masuk', 'Keluar', 'Opname', 'Rusak') then
    raise exception 'Jenis transaksi tidak valid';
  end if;

  if p_quantity is null or p_quantity = 'NaN'::numeric
     or p_quantity in ('Infinity'::numeric, '-Infinity'::numeric) or p_quantity < 0 then
    raise exception 'Jumlah tidak valid';
  end if;

  if p_type in ('Masuk', 'Keluar', 'Rusak') and p_quantity = 0 then
    raise exception 'Jumlah harus lebih dari 0';
  end if;

  if p_type = 'Rusak' and coalesce(trim(p_notes), '') = '' then
    raise exception 'Alasan rusak wajib diisi';
  end if;

  if p_unit_price is not null then
    if p_type <> 'Masuk' then
      raise exception 'Harga hanya untuk barang masuk';
    end if;
    if p_unit_price = 'NaN'::numeric or p_unit_price in ('Infinity'::numeric, '-Infinity'::numeric)
       or p_unit_price < 0 then
      raise exception 'Harga tidak valid';
    end if;
  end if;

  select i.division, i.quantity, i.purchase_price
    into v_division, v_before, v_price
  from public.lokalin_stock_items i
  where i.id = p_item_id
  for update;

  if not found then
    raise exception 'Barang tidak ditemukan';
  end if;

  if v_role not in ('owner', 'staff') and lower(v_division) <> v_role then
    raise exception 'Akses divisi ditolak';
  end if;

  if p_type = 'Masuk' then
    v_after := v_before + p_quantity;
    -- Harga rata-rata tertimbang (moving average) bila harga beli diisi.
    if p_unit_price is not null then
      v_price := case
        when v_before <= 0 or v_price is null then p_unit_price
        else round((v_before * v_price + p_quantity * p_unit_price) / v_after, 4)
      end;
    end if;
  elsif p_type in ('Keluar', 'Rusak') then
    v_after := v_before - p_quantity;
  else
    v_after := p_quantity;
  end if;

  if v_after < 0 then
    raise exception 'Stok tidak mencukupi';
  end if;

  update public.lokalin_stock_items
  set quantity = v_after, purchase_price = v_price
  where id = p_item_id;

  insert into public.lokalin_stock_transactions (
    item_id, transaction_type, quantity, quantity_before, quantity_after, notes, created_by, unit_price
  ) values (
    p_item_id, p_type, p_quantity, v_before, v_after, p_notes, auth.uid(), p_unit_price
  )
  returning id into v_transaction_id;

  return query select v_transaction_id, v_before, v_after;
end;
$function$;

revoke all on function public.lokalin_stock_record(uuid, text, numeric, text, numeric) from public, anon;
grant execute on function public.lokalin_stock_record(uuid, text, numeric, text, numeric) to authenticated;
