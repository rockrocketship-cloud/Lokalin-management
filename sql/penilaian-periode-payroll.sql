-- Periode hitung Penilaian Kinerja mengikuti periode payroll: bulan YYYY-MM berarti tanggal 26 bulan sebelumnya
-- sampai tanggal 25 bulan itu (contoh 2026-11 = 2026-10-26 sampai 2026-11-25), bukan bulan kalender.
-- Owner menjalankan file ini di Supabase SQL Editor, setelah sql/penilaian-lupa-pulang.sql.
-- Bot tidak menjalankan file ini ke Supabase live. Hanya Owner yang menerapkannya.
-- Hanya jendela tanggal yang berubah. Tipe kembalian sama, jadi CREATE OR REPLACE cukup tanpa DROP.
-- Aturan telat dan lupa pulang (tanggal hari ini Asia/Makassar dikecualikan) tidak berubah.
-- Skrip idempoten. Tidak menghapus data. RLS absensi_harian dibiarkan seperti semula.

begin;

create or replace function public.lokalin_penilaian_telat(p_periode text)
returns table (emp_id uuid, hadir integer, ringan integer, berat integer, lupa_pulang integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date;
  v_end date;
  v_today date := (now() at time zone 'Asia/Makassar')::date;
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_roles r where r.user_id = auth.uid()
  ) then
    raise exception 'Akses ditolak. Silakan login dengan akun Lokalin.';
  end if;
  if p_periode is null or p_periode !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Periode harus berformat YYYY-MM.';
  end if;
  v_end := (p_periode || '-25')::date;
  v_start := (v_end - interval '1 month' + interval '1 day')::date;

  return query
  with a as (
    select distinct on (e.id, h.tanggal::date)
      e.id as eid,
      h.tanggal::date as tgl,
      case lower(btrim(coalesce(h.shift, ''))) when 'pagi' then 600 when 'sore' then 960 end as mulai,
      (substring(h.jam_masuk::text from '^(\d{1,2}):')::int * 60
        + substring(h.jam_masuk::text from '^\d{1,2}:(\d{2})')::int) as menit,
      nullif(btrim(h.jam_pulang::text), '') is null as tanpa_pulang
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
    count(*) filter (where a.mulai is not null and a.menit - a.mulai > 15)::int,
    count(*) filter (where a.tanpa_pulang and a.tgl < v_today)::int
  from a
  group by a.eid;
end;
$$;

revoke all on function public.lokalin_penilaian_telat(text) from public, anon;
grant execute on function public.lokalin_penilaian_telat(text) to authenticated;

commit;
