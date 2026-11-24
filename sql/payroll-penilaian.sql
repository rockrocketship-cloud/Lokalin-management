-- Kolom penanda sumber penyesuaian Payroll untuk integrasi Penilaian Kinerja.
-- Owner menjalankan file ini sekali di Supabase SQL Editor. Bot tidak menjalankan file ini ke Supabase live.
-- Isi kolom source: 'penilaian' (otomatis dari Penilaian Kinerja) atau 'manual' (Owner mengubah bonus/potongan).
-- Skrip idempoten, hanya menambah kolom, tidak menghapus data, tidak mengubah RLS dan tabel penilaian_*.

alter table public.payroll_adjustments
  add column if not exists source text;
