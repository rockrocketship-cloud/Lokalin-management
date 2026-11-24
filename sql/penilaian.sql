-- Penilaian Kinerja bulanan untuk Lokalin Cafe.
-- Owner menjalankan file ini sekali di Supabase SQL Editor sebelum memakai halaman penilaian.html.
-- Bot tidak menjalankan file ini ke Supabase live. Hanya Owner yang menerapkannya.
-- Skrip idempoten, hanya membuat objek baru, tidak mengubah tabel lain, dan tidak mengisi data.
-- Owner boleh membaca, menambah, mengubah, dan menghapus. Akun lain yang login hanya boleh membaca.

begin;

-- Input mingguan supervisor: skor 1-5 per karyawan per minggu (week_start = tanggal awal minggu).
create table if not exists public.penilaian_mingguan (
  id uuid primary key default gen_random_uuid(),
  emp_id uuid not null references public.employees(id) on delete cascade,
  week_start date not null,
  kebersihan integer not null check (kebersihan between 1 and 5),
  sop_resep integer not null check (sop_resep between 1 and 5),
  kecepatan integer not null check (kecepatan between 1 and 5),
  updated_at timestamptz not null default now(),
  unique (emp_id, week_start)
);

-- Input bulanan manual: periode berupa bulan kalender YYYY-MM (bukan periode payroll 26-25).
create table if not exists public.penilaian_bulanan (
  id uuid primary key default gen_random_uuid(),
  emp_id uuid not null references public.employees(id) on delete cascade,
  periode text not null check (periode ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  pelayanan numeric not null default 20 check (pelayanan between 0 and 20),
  sikap numeric check (sikap is null or sikap between 0 and 15),
  inisiatif numeric check (inisiatif is null or inisiatif between 0 and 10),
  alpa_count integer not null default 0 check (alpa_count >= 0),
  ada_pelanggaran boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (emp_id, periode)
);

alter table public.penilaian_mingguan enable row level security;
alter table public.penilaian_bulanan enable row level security;

revoke all on public.penilaian_mingguan from public, anon;
revoke all on public.penilaian_bulanan from public, anon;
grant select, insert, update, delete on public.penilaian_mingguan to authenticated;
grant select, insert, update, delete on public.penilaian_bulanan to authenticated;

do $$
declare t text;
begin
  foreach t in array array['penilaian_mingguan','penilaian_bulanan'] loop
    execute format('drop policy if exists %I on public.%I', 'lokalin_read_' || t, t);
    execute format('drop policy if exists %I on public.%I', 'lokalin_owner_write_' || t, t);
    execute format('drop policy if exists %I on public.%I', 'lokalin_owner_update_' || t, t);
    execute format('drop policy if exists %I on public.%I', 'lokalin_owner_delete_' || t, t);

    -- Semua akun yang login boleh membaca.
    execute format('create policy %I on public.%I for select to authenticated using (true)',
      'lokalin_read_' || t, t);

    -- Hanya Owner yang boleh menulis.
    execute format($p$create policy %I on public.%I for insert to authenticated
      with check (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))$p$,
      'lokalin_owner_write_' || t, t);
    execute format($p$create policy %I on public.%I for update to authenticated
      using (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))
      with check (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))$p$,
      'lokalin_owner_update_' || t, t);
    execute format($p$create policy %I on public.%I for delete to authenticated
      using (exists (select 1 from public.app_roles r where r.user_id = (select auth.uid()) and r.role = 'owner'))$p$,
      'lokalin_owner_delete_' || t, t);
  end loop;
end $$;

commit;
