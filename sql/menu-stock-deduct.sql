-- Potong stok bahan gudang otomatis saat menu terjual di kasir (pos.html).
-- Owner harus menjalankan skrip ini sendiri di Supabase SQL Editor. Skrip tidak dijalankan otomatis.
-- Idempoten: aman dijalankan ulang. Menjalankan ulang tidak memotong stok dan tidak mengubah riwayat.
-- Prasyarat: sql/menu-stock-sync.sql sudah dijalankan (fungsi lokalin_menu_name_key dan tabel menu_stock_links).
--
-- Cara kerja
-- 1. pos_checkout tidak diganti. Skrip memasang trigger pada tabel baris pesanan POS.
--    Tabel itu dicari otomatis: tabel public yang punya foreign key ke public.pos_orders(id)
--    dan kolom product_id serta qty atau quantity. Jika tidak ketemu, skrip berhenti dengan pesan
--    yang mencantumkan semua tabel pos_* dan kolom yang dibutuhkan. Tidak ada tabel palsu yang dibuat.
-- 2. Trigger bersifat deferred dan berjalan di transaksi yang sama dengan checkout, tepat sebelum commit.
--    Semua baris pesanan sudah tersimpan saat trigger berjalan. Jika pemotongan gagal, seluruh penjualan dibatalkan.
-- 3. Pencocokan: pos_products.name dicocokkan dengan menu_availability.name lewat
--    public.lokalin_menu_name_key(name). Jika ada beberapa menu dengan kunci sama, dipakai id terkecil.
--    Produk tanpa menu yang cocok, atau menu tanpa hubungan di menu_stock_links, dilewati tanpa menggagalkan checkout.
-- 4. Hubungan dengan qty_per_serving NULL atau <= 0 dilewati. Yang dipotong hanya qty_per_serving x jumlah terjual.
-- 5. Setiap barang stok yang terpotong menghasilkan satu baris 'Keluar' di lokalin_stock_transactions
--    (item_id, transaction_type, quantity, quantity_before, quantity_after, notes) dan memperbarui
--    lokalin_stock_items.quantity. Trigger lokalin_stock_items_menu_sync tetap berjalan setelah update itu.
--    Trigger itu memakai helper privat public.lokalin_menu_stock_sync_apply (tanpa cek peran).
--    lokalin_stock_record tidak diubah. Stok POS (pos_products.stock_qty) tidak disentuh.
-- 6. Catatan transaksi berbentuk: Auto: <menu> x<jumlah>. Jika satu pesanan memakai satu bahan dari beberapa
--    menu, catatan berisi beberapa menu dipisah koma, dan dipotong maksimal 200 karakter.
--
-- Idempotensi
-- Tabel lokalin_pos_stock_deductions menyimpan kunci unik (id pesanan, id barang stok) beserta jumlah yang
-- sudah dipotong. Pemotongan bersifat bertahap per (pesanan, barang stok): baris pesanan (pos_orders) dikunci
-- (FOR UPDATE) lebih dulu, lalu kebutuhan dihitung dari semua baris pesanan saat ini.
-- Kebutuhan sama dengan yang sudah dipotong: tidak melakukan apa-apa (trigger berulang atau skrip dijalankan ulang).
-- Kebutuhan lebih besar (misalnya baris baru ditambahkan): hanya selisihnya yang dipotong.
-- Kebutuhan lebih kecil: DITOLAK dengan error, tidak ada pengembalian stok diam-diam.
-- Pesanan lama sebelum skrip ini dipasang tidak dipotong mundur.
-- Mengubah atau menghapus baris pesanan, atau menghapus pesanan atau mengganti id-nya, setelah stoknya dipotong
-- DITOLAK dengan error. Memindahkan baris ke atau dari pesanan yang sudah dipotong juga ditolak.
-- Koreksi dilakukan manual lewat transaksi stok 'Masuk' di stok.html.
--
-- Kebijakan stok kurang
-- Stok tidak pernah dibuat negatif diam-diam dan tidak dibulatkan ke 0. Jika salah satu bahan terhubung
-- akan turun di bawah 0, skrip melempar error, checkout dibatalkan, dan pesan menyebut nama bahan serta sisa stoknya.
-- Staf harus mengisi stok (Masuk atau Opname) sebelum menjual menu itu lagi.
--
-- Checkout oleh akun kasir (app_roles role kiosk) diizinkan. Update stok memicu sinkron menu lewat helper privat
-- public.lokalin_menu_stock_sync_apply, yang tidak mengecek peran. RPC lokalin_apply_menu_stock_sync tetap
-- mewajibkan owner/staff. Skrip ini memasang ulang helper dan fungsi trigger sinkron, sehingga kiosk tetap
-- bisa checkout meskipun versi lama sql/menu-stock-sync.sql sudah pernah dijalankan.
--
-- Hak akses: semua fungsi di sini hanya dipanggil trigger. Tidak ada grant ke anon atau authenticated.
-- Grant dan RLS tabel baris pesanan POS tidak diubah.
-- Tabel catatan pemotongan memakai RLS tanpa kebijakan, sehingga hanya fungsi security definer yang menulisnya.

begin;

do $pre$
declare
  tx_missing text;
  lines_tbl text;
  lines_cnt int;
  order_col text;
  prod_col text;
  qty_col text;
  pos_tables text;
begin
  if to_regclass('public.pos_orders') is null or to_regclass('public.pos_products') is null
     or to_regclass('public.menu_availability') is null or to_regclass('public.menu_stock_links') is null
     or to_regclass('public.lokalin_stock_items') is null or to_regclass('public.lokalin_stock_transactions') is null then
    raise exception 'Tabel pos_orders, pos_products, menu_availability, menu_stock_links, lokalin_stock_items, atau lokalin_stock_transactions belum ada. Jalankan sql/menu-stock-sync.sql dan pastikan tabel POS ada.';
  end if;
  if not exists (select 1 from information_schema.columns c
                 where c.table_schema = 'public' and c.table_name = 'menu_availability' and c.column_name = 'sync_level')
     or not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = 'menu_stock_links' and c.column_name = 'qty_per_serving') then
    raise exception 'Kolom menu_availability.sync_level atau menu_stock_links.qty_per_serving belum ada. Jalankan sql/menu-stock-sync.sql dahulu.';
  end if;
  if to_regprocedure('public.lokalin_menu_name_key(text)') is null then
    raise exception 'Fungsi public.lokalin_menu_name_key belum ada. Jalankan sql/menu-stock-sync.sql dahulu.';
  end if;

  -- Kolom wajib di tabel transaksi stok. Kolom lain yang NOT NULL tanpa default akan membuat insert gagal.
  if exists (
    select 1 from (values ('item_id'), ('transaction_type'), ('quantity'), ('quantity_before'), ('quantity_after'), ('notes')) v(n)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = 'lokalin_stock_transactions' and c.column_name = v.n)
  ) then
    raise exception 'lokalin_stock_transactions tidak punya semua kolom: item_id, transaction_type, quantity, quantity_before, quantity_after, notes.';
  end if;
  select string_agg(c.column_name, ', ') into tx_missing
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'lokalin_stock_transactions'
    and c.is_nullable = 'NO' and c.column_default is null and coalesce(c.is_identity, 'NO') = 'NO'
    and c.column_name not in ('item_id', 'transaction_type', 'quantity', 'quantity_before', 'quantity_after', 'notes');
  if tx_missing is not null then
    raise exception 'lokalin_stock_transactions punya kolom wajib tanpa default yang tidak diisi skrip ini: %', tx_missing;
  end if;

  select string_agg(distinct t.table_name, ', ') into pos_tables
  from information_schema.tables t
  where t.table_schema = 'public' and left(t.table_name, 4) = 'pos_';

  select count(*), min(cl.relname), min(a.attname) into lines_cnt, lines_tbl, order_col
  from pg_constraint k
  join pg_class cl on cl.oid = k.conrelid
  join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
  join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
  where k.contype = 'f'
    and k.confrelid = 'public.pos_orders'::regclass
    and array_length(k.conkey, 1) = 1
    and k.confkey[1] = (select pa.attnum from pg_attribute pa
                        where pa.attrelid = 'public.pos_orders'::regclass and pa.attname = 'id' and not pa.attisdropped)
    and exists (select 1 from information_schema.columns c
                where c.table_schema = 'public' and c.table_name = cl.relname and c.column_name = 'product_id')
    and exists (select 1 from information_schema.columns c
                where c.table_schema = 'public' and c.table_name = cl.relname and c.column_name in ('qty', 'quantity'));

  if lines_cnt = 0 then
    raise exception 'Tabel baris pesanan POS tidak ditemukan. Dibutuhkan tabel public dengan foreign key ke pos_orders.id, kolom product_id, dan kolom qty atau quantity. Tabel pos_* yang ada: %', coalesce(pos_tables, '(tidak ada)');
  elsif lines_cnt > 1 then
    raise exception 'Lebih dari satu tabel baris pesanan cocok. Skrip tidak menebak. Tabel pos_* yang ada: %', coalesce(pos_tables, '(tidak ada)');
  end if;

  prod_col := 'product_id';
  select c.column_name into qty_col
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = lines_tbl and c.column_name in ('qty', 'quantity')
  order by (c.column_name = 'qty') desc limit 1;

  -- Simpan hasil deteksi untuk blok DO berikutnya (berlaku hanya di transaksi ini).
  perform set_config('lokalin.lines_tbl', lines_tbl, true);
  perform set_config('lokalin.order_col', order_col, true);
  perform set_config('lokalin.prod_col', prod_col, true);
  perform set_config('lokalin.qty_col', qty_col, true);
end
$pre$;

-- Helper sinkron privat dan fungsi trigger sinkron. Sama dengan yang ada di sql/menu-stock-sync.sql.
-- Dipasang ulang di sini agar trigger lokalin_stock_items_menu_sync memakai helper tanpa cek peran.
create or replace function public.lokalin_menu_stock_sync_apply(p_menu_id uuid default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
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

revoke all on function public.lokalin_menu_stock_sync_apply(uuid) from public, anon, authenticated;

create or replace function public.lokalin_menu_stock_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
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
  -- Helper privat tanpa cek peran, supaya update stok oleh kasir (kiosk) lewat pos_checkout tidak ditolak.
  perform public.lokalin_menu_stock_sync_apply(target);
  return coalesce(new, old);
end;
$$;

revoke all on function public.lokalin_menu_stock_sync_trigger() from public, anon;

-- Catatan pemotongan: satu baris per (pesanan, barang stok). Kunci unik ini mencegah potong ganda.
create table if not exists public.lokalin_pos_stock_deductions (
  order_id text not null,
  stock_item_id uuid not null references public.lokalin_stock_items (id) on delete restrict,
  quantity numeric not null,
  created_at timestamptz not null default now(),
  primary key (order_id, stock_item_id)
);

alter table public.lokalin_pos_stock_deductions enable row level security;
revoke all on table public.lokalin_pos_stock_deductions from public, anon, authenticated;

do $build$
declare
  lines_tbl text := current_setting('lokalin.lines_tbl');
  order_col text := current_setting('lokalin.order_col');
  prod_col text := current_setting('lokalin.prod_col');
  qty_col text := current_setting('lokalin.qty_col');
  body text;
begin
  -- Fungsi inti: potong stok untuk satu pesanan. Nama kolom hasil deteksi disisipkan lewat replace().
  body := $fn$
create or replace function public.lokalin_pos_deduct_order(p_order text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $inner$
declare
  r record;
  v_before numeric;
  v_after numeric;
  v_delta numeric;
  v_note text;
begin
  if p_order is null then
    return;
  end if;

  -- Kunci pesanan sekali, sebelum cek stok. Pemanggil lain untuk pesanan yang sama menunggu di sini,
  -- lalu melihat catatan pemotongan yang sudah commit dan tidak melakukan apa-apa.
  perform 1 from public.pos_orders o where o.id::text = p_order for update;
  if not found then
    return;
  end if;

  for r in
    with needs as (
      select k.stock_item_id,
             sum(k.qty_per_serving * s.sold) as need,
             string_agg(m.name || ' x' || trim_scale(s.sold)::text, ', ' order by m.name) as menus
      from (
        select ln.__PROD__::text as pid, sum(ln.__QTY__::numeric) as sold
        from public.__LINES__ ln
        where ln.__ORDER__::text = p_order
        group by 1
      ) s
      join public.pos_products p on p.id::text = s.pid
      join lateral (
        select ma.id, ma.name
        from public.menu_availability ma
        where public.lokalin_menu_name_key(ma.name) = public.lokalin_menu_name_key(p.name)
        order by ma.id
        limit 1
      ) m on true
      join public.menu_stock_links k
        on k.menu_id = m.id and k.qty_per_serving is not null and k.qty_per_serving > 0
      where s.sold > 0
      group by k.stock_item_id
    ),
    done as (
      select d.stock_item_id, d.quantity
      from public.lokalin_pos_stock_deductions d
      where d.order_id = p_order
    )
    select coalesce(n.stock_item_id, d.stock_item_id) as stock_item_id,
           coalesce(n.need, 0) as need,
           coalesce(d.quantity, 0) as done,
           n.menus
    from needs n
    full join done d on d.stock_item_id = n.stock_item_id
    order by 1
  loop
    if r.need < r.done then
      raise exception 'Pesanan % sudah memotong stok % lebih banyak dari kebutuhan sekarang (dipotong %, butuh %). Tidak ada pengembalian otomatis. Koreksi stok manual lewat transaksi Masuk di stok.html.',
        p_order, (select i.name from public.lokalin_stock_items i where i.id = r.stock_item_id), r.done, r.need;
    end if;
    v_delta := r.need - r.done;
    if v_delta = 0 then
      continue;
    end if;

    select coalesce(i.quantity, 0) into v_before
    from public.lokalin_stock_items i
    where i.id = r.stock_item_id
    for update;
    if not found then
      continue;
    end if;

    v_after := v_before - v_delta;
    if v_after < 0 then
      raise exception 'Stok tidak cukup untuk checkout: % (sisa %, butuh %). Checkout dibatalkan.',
        (select i.name from public.lokalin_stock_items i where i.id = r.stock_item_id), v_before, v_delta;
    end if;

    insert into public.lokalin_pos_stock_deductions (order_id, stock_item_id, quantity)
    values (p_order, r.stock_item_id, r.need)
    on conflict (order_id, stock_item_id) do update set quantity = excluded.quantity;

    v_note := left('Auto: ' || r.menus, 200);

    insert into public.lokalin_stock_transactions
      (item_id, transaction_type, quantity, quantity_before, quantity_after, notes)
    values (r.stock_item_id, 'Keluar', v_delta, v_before, v_after, v_note);

    update public.lokalin_stock_items
    set quantity = v_after
    where id = r.stock_item_id;
  end loop;
end;
$inner$;
$fn$;
  body := replace(replace(replace(replace(body,
    '__LINES__', quote_ident(lines_tbl)),
    '__ORDER__', quote_ident(order_col)),
    '__PROD__', quote_ident(prod_col)),
    '__QTY__', quote_ident(qty_col));
  execute body;

  -- Trigger deferred pada baris pesanan: berjalan sekali per baris, tetapi pemotongan hanya sekali per pesanan.
  execute $fn$
create or replace function public.lokalin_pos_deduct_line_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $inner$
begin
  perform public.lokalin_pos_deduct_order(to_jsonb(new) ->> $fn$ || quote_literal(order_col) || $fn$);
  return null;
end;
$inner$;
$fn$;

  -- Penjaga: tolak ubah/hapus baris pesanan yang stoknya sudah dipotong, termasuk memindahkan baris
  -- ke atau dari pesanan yang sudah dipotong (id lama dan id baru sama-sama dicek). INSERT tidak diblokir:
  -- baris checkout yang sedang berjalan harus bisa masuk, dan baris tambahan dipotong selisihnya oleh trigger deferred.
  execute $fn$
create or replace function public.lokalin_pos_guard_line_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $inner$
declare
  v_old text;
  v_new text;
  v_hit text;
begin
  v_old := to_jsonb(old) ->> $fn$ || quote_literal(order_col) || $fn$;
  if tg_op = 'UPDATE' then
    v_new := to_jsonb(new) ->> $fn$ || quote_literal(order_col) || $fn$;
  end if;

  -- Kunci bersama baris pesanan agar pemotongan yang sedang commit selesai dulu sebelum dicek.
  perform 1 from public.pos_orders o where o.id::text in (v_old, v_new) order by o.id for share;

  select d.order_id into v_hit
  from public.lokalin_pos_stock_deductions d
  where d.order_id in (v_old, v_new)
  limit 1;
  if v_hit is not null then
    raise exception 'Pesanan % sudah memotong stok bahan. Baris pesanan tidak boleh diubah, dihapus, atau dipindahkan. Koreksi stok manual lewat transaksi Masuk di stok.html.', v_hit;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$inner$;
$fn$;

  execute 'drop trigger if exists lokalin_pos_deduct_stock on public.' || quote_ident(lines_tbl);
  execute 'create constraint trigger lokalin_pos_deduct_stock after insert on public.' || quote_ident(lines_tbl)
    || ' deferrable initially deferred for each row execute function public.lokalin_pos_deduct_line_trigger()';

  execute 'drop trigger if exists lokalin_pos_guard_lines on public.' || quote_ident(lines_tbl);
  execute 'create trigger lokalin_pos_guard_lines before update or delete on public.' || quote_ident(lines_tbl)
    || ' for each row execute function public.lokalin_pos_guard_line_trigger()';
end
$build$;

-- Penjaga pesanan: tolak hapus pesanan, atau ganti id pesanan, yang stoknya sudah dipotong.
create or replace function public.lokalin_pos_guard_order_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  -- Kunci baris pesanan dulu agar pemotongan yang sedang commit selesai sebelum dicek.
  perform 1 from public.pos_orders o where o.id = old.id for update;
  if exists (select 1 from public.lokalin_pos_stock_deductions d where d.order_id = old.id::text) then
    raise exception 'Pesanan % sudah memotong stok bahan. Pesanan tidak boleh dihapus atau diganti id-nya. Koreksi stok manual lewat transaksi Masuk di stok.html.', old.id;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists lokalin_pos_guard_orders on public.pos_orders;
create trigger lokalin_pos_guard_orders
before delete or update of id on public.pos_orders
for each row execute function public.lokalin_pos_guard_order_trigger();

revoke all on function public.lokalin_pos_deduct_order(text) from public, anon, authenticated;
revoke all on function public.lokalin_pos_deduct_line_trigger() from public, anon, authenticated;
revoke all on function public.lokalin_pos_guard_line_trigger() from public, anon, authenticated;
revoke all on function public.lokalin_pos_guard_order_trigger() from public, anon, authenticated;

commit;
