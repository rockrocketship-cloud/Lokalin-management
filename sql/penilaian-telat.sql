-- Hitung telat bulanan untuk Penilaian Kinerja dan Payroll Lokalin Cafe.
-- Owner menjalankan file ini di Supabase SQL Editor. Bot tidak menjalankan file ini ke Supabase live.
-- Skrip idempoten (create or replace), tidak mengubah tabel, kebijakan RLS, atau data.
-- Alasan: akun kiosk hanya boleh membaca absensi_harian hari ini, sehingga hitungan telat sebulan dari klien salah.
-- Fungsi ini SECURITY DEFINER dan hanya mengembalikan jumlah per karyawan (hadir, ringan, berat),
-- tanpa jam masuk, nama, atau tanggal. Aturan sama dengan kehadiran() di penilaian-hitung.js:
-- satu baris per karyawan per tanggal (jam masuk paling awal), Pagi mulai 10:00, Sore mulai 16:00,
-- telat 1-15 menit = ringan, lebih dari 15 menit = berat, shift tidak dikenal dihitung hadir tanpa telat.

begin;

create or replace function public.lokalin_penilaian_telat(p_periode text)
returns table (emp_id uuid, hadir integer, ringan integer, berat integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date;
  v_end date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_roles r where r.user_id = auth.uid()
  ) then
    raise exception 'Akses ditolak. Silakan login dengan akun Lokalin.';
  end if;
  if p_periode is null or p_periode !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Periode harus berformat YYYY-MM.';
  end if;
  v_start := (p_periode || '-01')::date;
  v_end := (v_start + interval '1 month - 1 day')::date;

  return query
  with a as (
    select distinct on (e.id, h.tanggal::date)
      e.id as eid,
      case lower(btrim(coalesce(h.shift, ''))) when 'pagi' then 600 when 'sore' then 960 end as mulai,
      (substring(h.jam_masuk::text from '^(\d{1,2}):')::int * 60
        + substring(h.jam_masuk::text from '^\d{1,2}:(\d{2})')::int) as menit
    from public.absensi_harian h
    join public.employees e
      on (nullif(h.emp_id::text, '') is not null and h.emp_id::text = e.id::text)
      or (nullif(h.emp_id::text, '') is null and lower(btrim(coalesce(h.nama, ''))) = lower(btrim(e.name)))
    where h.tanggal::date between v_start and v_end
      and h.jam_masuk is not null
      and h.jam_masuk::text ~ '^\d{1,2}:\d{2}'
    order by e.id, h.tanggal::date, h.jam_masuk::text
  )
  select a.eid,
    count(*)::int,
    count(*) filter (where a.mulai is not null and a.menit - a.mulai between 1 and 15)::int,
    count(*) filter (where a.mulai is not null and a.menit - a.mulai > 15)::int
  from a
  group by a.eid;
end;
$$;

revoke all on function public.lokalin_penilaian_telat(text) from public, anon;
grant execute on function public.lokalin_penilaian_telat(text) to authenticated;

commit;
