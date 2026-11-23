-- Kontrol Telur untuk Lokalin Cafe.
-- Owner menjalankan skrip ini sekali di Supabase SQL Editor sebelum memakai halaman telur.html.
-- Skrip ini idempoten, jadi aman dijalankan ulang.
-- Skrip ini hanya membuat atau memperbarui objek milik Kontrol Telur dan tidak menghapus data lain.
-- Skrip ini tidak mengisi resep atau angka telur apa pun. Owner mengisinya lewat halaman.

begin;

-- Fungsi hak akses ini sama dengan yang ada di sql/menu-stock-sync.sql.
-- Isinya disalin agar skrip ini aman dijalankan walau skrip lain belum dipakai.
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

-- Resep telur: satu baris per nama menu, tidak dipisah per porsi Normal atau Reguler.
create table if not exists public.telur_resep (
  menu_name text primary key check (length(trim(menu_name)) > 0),
  telur_per_porsi numeric not null check (telur_per_porsi >= 0),
  updated_at timestamptz not null default now()
);

-- Log harian telur: satu baris per tanggal. stok_akhir kosong sampai stok fisik dihitung.
create table if not exists public.telur_log_harian (
  tanggal date primary key,
  stok_awal numeric not null check (stok_awal >= 0),
  telur_masuk numeric not null default 0 check (telur_masuk >= 0),
  stok_akhir numeric check (stok_akhir >= 0),
  rusak numeric not null default 0 check (rusak >= 0),
  alasan_rusak text,
  check (rusak = 0 or length(trim(coalesce(alasan_rusak, ''))) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Penjualan harian per menu, diisi manual karena belum ada tabel penjualan per menu.
create table if not exists public.telur_penjualan_harian (
  tanggal date not null,
  menu_name text not null check (length(trim(menu_name)) > 0),
  qty numeric not null check (qty >= 0),
  updated_at timestamptz not null default now(),
  primary key (tanggal, menu_name)
);

-- Pengaturan: tepat satu baris (id = 1) berisi batas selisih telur.
create table if not exists public.telur_pengaturan (
  id integer primary key check (id = 1),
  batas_selisih numeric not null default 3 check (batas_selisih >= 0),
  updated_at timestamptz not null default now()
);

insert into public.telur_pengaturan (id, batas_selisih)
values (1, 3)
on conflict (id) do nothing;

-- RLS: hanya pengguna login dengan peran owner atau staf yang boleh membaca dan menulis.
-- Anon tidak punya akses sama sekali.
alter table public.telur_resep enable row level security;
alter table public.telur_log_harian enable row level security;
alter table public.telur_penjualan_harian enable row level security;
alter table public.telur_pengaturan enable row level security;

revoke all on public.telur_resep from public, anon;
revoke all on public.telur_log_harian from public, anon;
revoke all on public.telur_penjualan_harian from public, anon;
revoke all on public.telur_pengaturan from public, anon;

grant select, insert, update, delete on public.telur_resep to authenticated;
grant select, insert, update, delete on public.telur_log_harian to authenticated;
grant select, insert, update, delete on public.telur_penjualan_harian to authenticated;
grant select, insert, update on public.telur_pengaturan to authenticated;

drop policy if exists telur_resep_manage on public.telur_resep;
create policy telur_resep_manage on public.telur_resep
  for all to authenticated
  using (public.lokalin_can_manage_menu_stock())
  with check (public.lokalin_can_manage_menu_stock());

drop policy if exists telur_log_harian_manage on public.telur_log_harian;
create policy telur_log_harian_manage on public.telur_log_harian
  for all to authenticated
  using (public.lokalin_can_manage_menu_stock())
  with check (public.lokalin_can_manage_menu_stock());

drop policy if exists telur_penjualan_harian_manage on public.telur_penjualan_harian;
create policy telur_penjualan_harian_manage on public.telur_penjualan_harian
  for all to authenticated
  using (public.lokalin_can_manage_menu_stock())
  with check (public.lokalin_can_manage_menu_stock());

drop policy if exists telur_pengaturan_manage on public.telur_pengaturan;
create policy telur_pengaturan_manage on public.telur_pengaturan
  for all to authenticated
  using (public.lokalin_can_manage_menu_stock())
  with check (public.lokalin_can_manage_menu_stock());

commit;
