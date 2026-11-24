-- Penalti "tidak update stok" untuk Penilaian Kinerja Lokalin Cafe.
-- Owner menjalankan file ini sekali di Supabase SQL Editor, setelah sql/penilaian.sql dan sql/penilaian-potongan.sql.
-- Bot tidak menjalankan file ini ke Supabase live. Hanya Owner yang menerapkannya.
-- Skrip idempoten: hanya ADD COLUMN IF NOT EXISTS, tidak menghapus data, tidak mengubah RLS. Baris lama tetap ada dan mendapat nilai default.

begin;

alter table public.penilaian_pengaturan
  add column if not exists potongan_tidak_update_stok integer not null default 5000 check (potongan_tidak_update_stok >= 0);

alter table public.penilaian_bulanan
  add column if not exists tidak_update_stok integer not null default 0 check (tidak_update_stok >= 0);

commit;
