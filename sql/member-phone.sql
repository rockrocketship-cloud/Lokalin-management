-- Simpan dan ubah nomor HP member oleh staf (dialog Kartu Member di dashboard).
-- Idempoten: aman dijalankan ulang di Supabase SQL Editor.
--
-- Cara kerja
-- 1. Tabel member dicari otomatis: satu tabel public yang punya kolom code, member_name,
--    dan balance. Jika tidak ada atau lebih dari satu, skrip berhenti dengan pesan error.
-- 2. Kolom phone (text, nullable) ditambahkan jika belum ada. Isinya hanya nomor ternormalisasi
--    (CHECK + indeks unik parsial), format 628 + 7 sampai 12 digit.
-- 3. public.lokalin_normalize_phone: ambil digit saja; awalan 0 jadi 62; awalan 8 diberi 62;
--    awalan 62 dipertahankan; selain itu NULL. Sama dengan aturan di lokalin-call.
-- 4. public.lokalin_set_member_phone(p_code, p_phone): hanya pengguna login dengan peran
--    owner atau kiosk di app_roles. p_phone NULL hanya membaca. String kosong menghapus nomor.
--    Nomor tidak valid atau
--    sudah dipakai member lain ditolak dengan pesan Indonesia.
--
-- Hak akses
-- RPC: REVOKE ALL dari PUBLIC dan anon, GRANT EXECUTE hanya ke authenticated.
-- Tabel member dan app_roles tidak diubah hak aksesnya. Sebelum produksi, pastikan
-- anon tidak bisa SELECT/UPDATE tabel member, dan pengguna biasa tidak bisa menulis app_roles.
-- Fungsi normalisasi: tidak diberikan ke PUBLIC/anon/authenticated.
-- Hak akses tabel member dan fungsi lokalin_stamp_card tidak diubah.

begin;

create or replace function public.lokalin_normalize_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $norm$
declare
  d text;
begin
  if p_phone is null or char_length(p_phone) > 40 then
    return null;
  end if;
  d := regexp_replace(p_phone, '[^0-9]', '', 'g');
  if left(d, 1) = '0' then
    d := '62' || substr(d, 2);
  elsif left(d, 1) = '8' then
    d := '62' || d;
  end if;
  if d ~ '^628[0-9]{7,12}$' then
    return d;
  end if;
  return null;
end;
$norm$;

revoke all on function public.lokalin_normalize_phone(text) from public, anon, authenticated;

do $build$
declare
  member_tables text[];
  member_table text;
begin
  select array_agg(t.table_name order by t.table_name) into member_tables
  from information_schema.tables t
  where t.table_schema = 'public'
    and t.table_type = 'BASE TABLE'
    and (
      select count(distinct c.column_name)
      from information_schema.columns c
      where c.table_schema = t.table_schema
        and c.table_name = t.table_name
        and c.column_name in ('code', 'member_name', 'balance')
    ) = 3;

  if member_tables is null then
    raise exception 'Tabel member tidak ditemukan: butuh satu tabel public dengan kolom code, member_name, balance.';
  elsif array_length(member_tables, 1) > 1 then
    raise exception 'Tabel member ambigu (lebih dari satu cocok): %', array_to_string(member_tables, ', ');
  end if;
  member_table := member_tables[1];

  execute format('alter table public.%I add column if not exists phone text', member_table);

  if not exists (
    select 1 from pg_constraint
    where conrelid = format('public.%I', member_table)::regclass
      and conname = 'lokalin_member_phone_normalized_chk'
  ) then
    execute format(
      'alter table public.%I add constraint lokalin_member_phone_normalized_chk check (phone is null or phone ~ %L)',
      member_table, '^628[0-9]{7,12}$');
  end if;

  execute format(
    'create unique index if not exists lokalin_member_phone_uidx on public.%I (phone) where phone is not null',
    member_table);

  execute format($fn$
    create or replace function public.lokalin_set_member_phone(p_code text, p_phone text)
    returns json
    language plpgsql
    security definer
    set search_path = pg_catalog, pg_temp
    as $body$
    declare
      v_phone text;
      v_row jsonb;
    begin
      if auth.uid() is null or not exists (
        select 1 from public.app_roles r
        where r.user_id = auth.uid() and r.role in ('owner', 'kiosk')
      ) then
        raise exception 'Akses ditolak.';
      end if;

      if p_code is null or btrim(p_code) = '' then
        raise exception 'Member tidak ditemukan.';
      end if;

      -- p_phone NULL = baca saja, jangan ubah. String kosong = hapus nomor.
      if p_phone is null then
        select to_jsonb(m) into v_row
        from public.%I m
        where lower(btrim(m.code::text)) = lower(btrim(p_code))
        limit 1;
      else
        if btrim(p_phone) = '' then
          v_phone := null;
        else
          v_phone := public.lokalin_normalize_phone(p_phone);
          if v_phone is null then
            raise exception 'Nomor HP tidak valid.';
          end if;
        end if;

        begin
          update public.%I m set phone = v_phone
          where lower(btrim(m.code::text)) = lower(btrim(p_code))
          returning to_jsonb(m) into v_row;
        exception when unique_violation then
          raise exception 'Nomor HP sudah terpakai.';
        end;
      end if;

      if v_row is null then
        raise exception 'Member tidak ditemukan.';
      end if;

      -- revision ikut dikembalikan jika kolomnya ada (NULL jika tidak).
      return json_build_object(
        'code', v_row->>'code',
        'member_name', v_row->>'member_name',
        'phone', v_row->>'phone',
        'balance', (v_row->>'balance')::numeric,
        'revision', v_row->'revision'
      );
    end;
    $body$;
  $fn$, member_table, member_table);
end
$build$;

revoke all on function public.lokalin_set_member_phone(text, text) from public, anon, authenticated;
grant execute on function public.lokalin_set_member_phone(text, text) to authenticated;

commit;
