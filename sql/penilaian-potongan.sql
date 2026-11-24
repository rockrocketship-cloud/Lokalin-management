-- Pengaturan potongan gaji untuk Penilaian Kinerja Lokalin Cafe.
-- Owner menjalankan file ini sekali di Supabase SQL Editor setelah sql/penilaian.sql dan sebelum memakai potongan gaji di penilaian.html.
-- Bot tidak menjalankan file ini ke Supabase live. Hanya Owner yang menerapkannya.
-- Skrip idempoten, hanya membuat objek baru, tidak menghapus data, dan tidak mengubah tabel lain.
-- Semua akun yang login boleh membaca. Hanya Owner yang boleh menambah dan mengubah.

begin;

-- Satu baris saja (id = 1). Nominal dalam rupiah.
create table if not exists public.penilaian_pengaturan (
  id integer primary key default 1 check (id = 1),
  potongan_telat_ringan integer not null default 5000 check (potongan_telat_ringan >= 0),
  potongan_telat_berat integer not null default 10000 check (potongan_telat_berat >= 0),
  potongan_alpa integer not null default 50000 check (potongan_alpa >= 0),
  hangus_di_bawah integer not null default 60 check (hangus_di_bawah between 0 and 100),
  updated_at timestamptz not null default now()
);

insert into public.penilaian_pengaturan (id) values (1) on conflict (id) do nothing;

alter table public.penilaian_pengaturan enable row level security;

revoke all on public.penilaian_pengaturan from public, anon;
grant select, insert, update on public.penilaian_pengaturan to authenticated;

drop policy if exists lokalin_read_penilaian_pengaturan on public.penilaian_pengaturan;
drop policy if exists lokalin_owner_write_penilaian_pengaturan on public.penilaian_pengaturan;
drop policy if exists lokalin_owner_update_penilaian_pengaturan on public.penilaian_pengaturan;

create policy lokalin_read_penilaian_pengaturan on public.penilaian_pengaturan
  for select to authenticated using (true);

create policy lokalin_owner_write_penilaian_pengaturan on public.penilaian_pengaturan
  for insert to authenticated
  with check (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'));

create policy lokalin_owner_update_penilaian_pengaturan on public.penilaian_pengaturan
  for update to authenticated
  using (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))
  with check (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'));

commit;
