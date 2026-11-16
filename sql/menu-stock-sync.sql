-- Sinkron ketersediaan menu dengan stok Bar/Kitchen.
-- Idempoten: aman dijalankan ulang di Supabase SQL Editor.
--
-- Cara kerja
-- 1. Tabel menu_stock_links menghubungkan satu menu ke satu atau lebih barang stok.
-- 2. Jika ada bahan dengan jumlah <= 0, menu otomatis menjadi tidak siap (sync_level = out).
-- 3. Jika semua bahan masih ada, tetapi ada yang <= stok minimum, menu tetap siap dan ditandai menipis (low).
-- 4. availability_mode = 'manual' menahan status is_ready yang dipilih staf. Mode 'auto' mengikuti stok.
-- 5. Menu tanpa hubungan bahan tidak diubah.
-- 6. qty_per_serving opsional: jika diisi, menu habis saat stok bahan kurang dari angka itu.
--    NULL = habis hanya jika stok <= 0. Angka ini tidak mengurangi stok saat menu terjual.
--
-- Anon tetap hanya bisa membaca menu_availability (kebijakan SELECT yang sudah ada).
-- Tulisan hanya untuk pengguna login yang punya peran owner/staff di app_roles atau lokalin_stock_roles.
--
-- Harga
-- Kolom price tetap harga Normal dan tidak ditimpa.
-- Kolom harga_reguler diisi dari foto menu porsi reguler.
-- Menu baru yang belum punya harga Normal disimpan dengan price NULL.
--
-- Kasir (pos_products) hanya punya satu kolom price, dan halaman POS belum memilih porsi.
-- Skrip ini tidak menulis ke pos_products agar harga yang sedang dipakai kasir tidak berubah.
-- Langkah berikut: tambah harga_reguler di pos_products dan pilihan Normal/Reguler di kasir.
--
-- Bahan stok satu hubungan per menu, tidak dipisah per porsi. Foto hanya merinci bahan
-- porsi reguler; porsi Normal memakai hubungan yang sama sampai owner memecahnya.

begin;

do $pre$
declare
  menu_udt text;
  stock_udt text;
begin
  select c.udt_name into menu_udt
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'menu_availability' and c.column_name = 'id';
  select c.udt_name into stock_udt
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'lokalin_stock_items' and c.column_name = 'id';
  if menu_udt is null or stock_udt is null then
    raise exception 'Tabel public.menu_availability atau public.lokalin_stock_items belum ada.';
  end if;
  if menu_udt <> 'uuid' or stock_udt <> 'uuid' then
    raise exception 'Skrip mengharapkan kolom id bertipe uuid. menu_availability.id=% lokalin_stock_items.id=%', menu_udt, stock_udt;
  end if;
end
$pre$;

alter table public.menu_availability
  add column if not exists availability_mode text,
  add column if not exists sync_level text,
  add column if not exists harga_reguler numeric;

do $price_nullable$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'menu_availability'
      and column_name = 'price'
      and is_nullable = 'NO'
  ) then
    alter table public.menu_availability alter column price drop not null;
  end if;
end
$price_nullable$;

create or replace function public.lokalin_menu_name_key(p text)
returns text
language sql
immutable
as $$
  select trim(both from regexp_replace(
    replace(replace(lower(coalesce(p, '')), 'palleko', 'palekko'), 'blackpepper', 'black pepper'),
    '\s+',
    ' ',
    'g'
  ));
$$;

update public.menu_availability
set availability_mode = 'manual'
where availability_mode is null;

alter table public.menu_availability
  alter column availability_mode set default 'manual';
alter table public.menu_availability
  alter column availability_mode set not null;

alter table public.menu_availability drop constraint if exists menu_availability_mode_check;
alter table public.menu_availability
  add constraint menu_availability_mode_check
  check (availability_mode in ('auto', 'manual'));

alter table public.menu_availability drop constraint if exists menu_availability_sync_level_check;
alter table public.menu_availability
  add constraint menu_availability_sync_level_check
  check (sync_level is null or sync_level in ('ok', 'low', 'out'));

create table if not exists public.menu_stock_links (
  id uuid primary key default gen_random_uuid(),
  menu_id uuid not null references public.menu_availability (id) on delete cascade,
  stock_item_id uuid not null references public.lokalin_stock_items (id) on delete cascade,
  -- Perkiraan kebutuhan satu porsi, dalam satuan barang stok. NULL = abaikan jumlah,
  -- menu dianggap habis hanya ketika stok bahan <= 0. Tidak mengurangi stok saat terjual.
  qty_per_serving numeric,
  created_at timestamptz not null default now(),
  unique (menu_id, stock_item_id)
);

alter table public.menu_stock_links
  add column if not exists qty_per_serving numeric;

create index if not exists menu_stock_links_stock_item_idx
  on public.menu_stock_links (stock_item_id);

alter table public.menu_stock_links enable row level security;

revoke all on table public.menu_stock_links from public, anon;
grant select, insert, update, delete on table public.menu_stock_links to authenticated;

create or replace function public.lokalin_can_manage_menu_stock()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from public.lokalin_stock_roles r
      where r.user_id = auth.uid() and r.role in ('owner', 'staff')
    )
    or exists (
      select 1 from public.app_roles r
      where r.user_id = auth.uid() and r.role in ('owner', 'staff')
    );
$$;

revoke all on function public.lokalin_can_manage_menu_stock() from public, anon;
grant execute on function public.lokalin_can_manage_menu_stock() to authenticated;

drop policy if exists menu_stock_links_manage on public.menu_stock_links;
create policy menu_stock_links_manage
on public.menu_stock_links
for all
to authenticated
using (public.lokalin_can_manage_menu_stock())
with check (public.lokalin_can_manage_menu_stock());

drop policy if exists menu_availability_staff_update on public.menu_availability;
create policy menu_availability_staff_update
on public.menu_availability
for update
to authenticated
using (public.lokalin_can_manage_menu_stock())
with check (public.lokalin_can_manage_menu_stock());

create or replace function public.lokalin_apply_menu_stock_sync(p_menu_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.lokalin_can_manage_menu_stock() then
    raise exception 'Tidak punya akses untuk menyinkronkan menu dan stok';
  end if;

  update public.menu_availability m
  set
    sync_level = case
      when agg.is_out then 'out'
      when agg.is_low then 'low'
      else 'ok'
    end,
    is_ready = case
      when m.availability_mode = 'auto' then not agg.is_out
      else m.is_ready
    end
  from (
    select
      l.menu_id,
      bool_or(
        coalesce(i.quantity, 0) <= 0
        or (
          l.qty_per_serving is not null
          and l.qty_per_serving > 0
          and coalesce(i.quantity, 0) < l.qty_per_serving
        )
      ) as is_out,
      bool_or(
        coalesce(i.quantity, 0) > 0
        and (l.qty_per_serving is null or coalesce(i.quantity, 0) >= l.qty_per_serving)
        and coalesce(i.quantity, 0) <= coalesce(i.minimum_stock, 0)
      ) as is_low
    from public.menu_stock_links l
    join public.lokalin_stock_items i on i.id = l.stock_item_id
    where p_menu_id is null or l.menu_id = p_menu_id
    group by l.menu_id
  ) agg
  where m.id = agg.menu_id;

  update public.menu_availability m
  set sync_level = null
  where (p_menu_id is null or m.id = p_menu_id)
    and not exists (
      select 1 from public.menu_stock_links l where l.menu_id = m.id
    );
end;
$$;

revoke all on function public.lokalin_apply_menu_stock_sync(uuid) from public, anon;
grant execute on function public.lokalin_apply_menu_stock_sync(uuid) to authenticated;

create or replace function public.lokalin_menu_stock_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  if tg_table_name = 'menu_stock_links' then
    target := coalesce(new.menu_id, old.menu_id);
  elsif tg_table_name = 'menu_availability' then
    target := new.id;
  else
    target := null;
  end if;
  perform public.lokalin_apply_menu_stock_sync(target);
  return coalesce(new, old);
end;
$$;

revoke all on function public.lokalin_menu_stock_sync_trigger() from public, anon;

drop trigger if exists lokalin_stock_items_menu_sync on public.lokalin_stock_items;
create trigger lokalin_stock_items_menu_sync
after update of quantity, minimum_stock on public.lokalin_stock_items
for each row
when (
  old.quantity is distinct from new.quantity
  or old.minimum_stock is distinct from new.minimum_stock
)
execute function public.lokalin_menu_stock_sync_trigger();

drop trigger if exists lokalin_menu_stock_links_sync on public.menu_stock_links;
create trigger lokalin_menu_stock_links_sync
after insert or update or delete on public.menu_stock_links
for each row
execute function public.lokalin_menu_stock_sync_trigger();

drop trigger if exists lokalin_menu_mode_sync on public.menu_availability;
create trigger lokalin_menu_mode_sync
after update of availability_mode on public.menu_availability
for each row
when (old.availability_mode is distinct from new.availability_mode)
execute function public.lokalin_menu_stock_sync_trigger();

-- Menu porsi reguler yang belum ada. price (Normal) dikosongkan supaya owner mengisinya.
-- harga_reguler mengikuti foto. Baris yang sudah ada, termasuk beda ejaan, tidak dibuat dobel.
insert into public.menu_availability (category, name, price, harga_reguler, is_ready, stock_qty, sort_order)
select v.category, v.name, null, v.harga_reguler, true, 0,
       (select coalesce(max(m.sort_order), 0) from public.menu_availability m) + v.n
from (values
  (1, 'Rice Bowl', 'Salted Egg Chicken', 35000),
  (2, 'Nasi Goreng', 'Nasi Goreng Seafood', 40000),
  (3, 'Indomie', 'Indomie Goreng Telur', 20000),
  (4, 'Indomie', 'Indomie Goreng Spesial', 28000),
  (5, 'Roti Bakar', 'Roti Bakar Keju', 25000),
  (6, 'Roti Bakar', 'Roti Bakar Coklat', 25000)
) as v(n, category, name, harga_reguler)
where not exists (
  select 1 from public.menu_availability m
  where public.lokalin_menu_name_key(m.name) = public.lokalin_menu_name_key(v.name)
);

-- Isi harga Reguler untuk 11 menu foto. Kolom price (Normal) tidak disentuh.
update public.menu_availability m
set harga_reguler = v.harga_reguler
from (values
  ('Paru Rica', 35000),
  ('Salted Egg Shrimp', 38000),
  ('Salted Egg Chicken', 35000),
  ('Ayam Palekko', 35000),
  ('Beef Black Pepper', 40000),
  ('Nasi Goreng Lokalin', 38000),
  ('Nasi Goreng Seafood', 40000),
  ('Indomie Goreng Telur', 20000),
  ('Indomie Goreng Spesial', 28000),
  ('Roti Bakar Keju', 25000),
  ('Roti Bakar Coklat', 25000)
) as v(name, harga_reguler)
where public.lokalin_menu_name_key(m.name) = public.lokalin_menu_name_key(v.name);

-- TINJAUAN OWNER — hubungan menu ke bahan.
-- qty di kolom ketiga adalah perkiraan "berapa satuan stok untuk satu porsi".
-- NULL = menu baru habis ketika stok bahan 0. Ubah nama agar persis sama dengan
-- lokalin_stock_items.name (huruf besar/kecil diabaikan). Barang yang belum ada
-- tidak dibuat di sini; baris itu dilewati.
-- Perkiraan yang perlu dicek ulang sebelum dianggap final:
--   roti tawar 2 lembar, telur 1, indomie 1 bungkus, ayam/udang/cumi/sapi/paru 1 satuan.
insert into public.menu_stock_links (menu_id, stock_item_id, qty_per_serving)
select m.id, s.id, v.qty
from (values
  ('Paru Rica', null, 'paru', 1::numeric),
  ('Paru Rica', null, 'cabai rawit', 1),
  ('Paru Rica', null, 'kemangi', 1),
  ('Salted Egg Shrimp', null, 'udang', 1),
  ('Salted Egg Shrimp', null, 'telur asin', 1),
  ('Salted Egg Shrimp', null, 'daun kari', 1),
  ('Salted Egg Chicken', null, 'ayam', 1),
  ('Salted Egg Chicken', null, 'telur asin', 1),
  ('Salted Egg Chicken', null, 'daun kari', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'ayam', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'cabai', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'asam', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'sapi', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'lada', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'bawang bombay', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'paprika', 1),
  ('Nasi Goreng Lokalin', null, 'nasi', 1),
  ('Nasi Goreng Lokalin', null, 'ayam', 1),
  ('Nasi Goreng Lokalin', null, 'telur', 1),
  ('Nasi Goreng Seafood', null, 'nasi', 1),
  ('Nasi Goreng Seafood', null, 'udang', 1),
  ('Nasi Goreng Seafood', null, 'cumi', 1),
  ('Nasi Goreng Seafood', null, 'telur', 1),
  ('Nasi Goreng Seafood', null, 'daun bawang', 1),
  ('Indomie Goreng Telur', null, 'indomie', 1),
  ('Indomie Goreng Telur', null, 'telur', 1),
  ('Indomie Goreng Telur', null, 'bawang goreng', 1),
  ('Indomie Goreng Telur', null, 'cabai', 1),
  ('Indomie Goreng Spesial', null, 'indomie', 1),
  ('Indomie Goreng Spesial', null, 'telur', 1),
  ('Indomie Goreng Spesial', null, 'kornet', 1),
  ('Indomie Goreng Spesial', null, 'keju', 1),
  ('Indomie Goreng Spesial', null, 'cabai rawit', 1),
  ('Roti Bakar Keju', null, 'roti tawar', 2),
  ('Roti Bakar Keju', null, 'keju', 1),
  ('Roti Bakar Keju', null, 'mentega', 1),
  ('Roti Bakar Coklat', null, 'roti tawar', 2),
  ('Roti Bakar Coklat', null, 'coklat', 1),
  ('Roti Bakar Coklat', null, 'mentega', 1)
) as v(menu_name, menu_alias, stock_name, qty)
join public.menu_availability m
  on lower(m.name) = lower(v.menu_name)
  or (v.menu_alias is not null and lower(m.name) = lower(v.menu_alias))
join public.lokalin_stock_items s
  on lower(s.name) = lower(v.stock_name)
on conflict (menu_id, stock_item_id) do nothing;

-- Hasil tinjauan: stock_id kosong = nama bahan belum ada, jadi hubungan tadi dilewati.
select v.menu_name, v.menu_alias, v.stock_name, v.qty as qty_per_serving_usulan,
       m.id as menu_id, s.id as stock_id
from (values
  ('Paru Rica', null, 'paru', 1::numeric),
  ('Paru Rica', null, 'cabai rawit', 1),
  ('Paru Rica', null, 'kemangi', 1),
  ('Salted Egg Shrimp', null, 'udang', 1),
  ('Salted Egg Shrimp', null, 'telur asin', 1),
  ('Salted Egg Shrimp', null, 'daun kari', 1),
  ('Salted Egg Chicken', null, 'ayam', 1),
  ('Salted Egg Chicken', null, 'telur asin', 1),
  ('Salted Egg Chicken', null, 'daun kari', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'ayam', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'cabai', 1),
  ('Ayam Palekko', 'Ayam Palleko', 'asam', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'sapi', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'lada', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'bawang bombay', 1),
  ('Beef Black Pepper', 'Beef Blackpepper', 'paprika', 1),
  ('Nasi Goreng Lokalin', null, 'nasi', 1),
  ('Nasi Goreng Lokalin', null, 'ayam', 1),
  ('Nasi Goreng Lokalin', null, 'telur', 1),
  ('Nasi Goreng Seafood', null, 'nasi', 1),
  ('Nasi Goreng Seafood', null, 'udang', 1),
  ('Nasi Goreng Seafood', null, 'cumi', 1),
  ('Nasi Goreng Seafood', null, 'telur', 1),
  ('Nasi Goreng Seafood', null, 'daun bawang', 1),
  ('Indomie Goreng Telur', null, 'indomie', 1),
  ('Indomie Goreng Telur', null, 'telur', 1),
  ('Indomie Goreng Telur', null, 'bawang goreng', 1),
  ('Indomie Goreng Telur', null, 'cabai', 1),
  ('Indomie Goreng Spesial', null, 'indomie', 1),
  ('Indomie Goreng Spesial', null, 'telur', 1),
  ('Indomie Goreng Spesial', null, 'kornet', 1),
  ('Indomie Goreng Spesial', null, 'keju', 1),
  ('Indomie Goreng Spesial', null, 'cabai rawit', 1),
  ('Roti Bakar Keju', null, 'roti tawar', 2),
  ('Roti Bakar Keju', null, 'keju', 1),
  ('Roti Bakar Keju', null, 'mentega', 1),
  ('Roti Bakar Coklat', null, 'roti tawar', 2),
  ('Roti Bakar Coklat', null, 'coklat', 1),
  ('Roti Bakar Coklat', null, 'mentega', 1)
) as v(menu_name, menu_alias, stock_name, qty)
left join public.menu_availability m
  on lower(m.name) = lower(v.menu_name)
  or (v.menu_alias is not null and lower(m.name) = lower(v.menu_alias))
left join public.lokalin_stock_items s
  on lower(s.name) = lower(v.stock_name)
order by v.menu_name, v.stock_name;

commit;
