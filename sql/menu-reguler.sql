-- Menu reguler (foto menu cetak) ke tabel ketersediaan: public.menu_availability.
-- Idempoten: aman dijalankan ulang di Supabase SQL Editor.
-- Tidak menulis ke data live dari agent ini; owner yang menjalankan skrip.
--
-- Isi 8 menu: Rice Bowl (5), Nasi Goreng Lokalin, Indomie Goreng Telur, Indomie Goreng Spesial.
-- Sengaja tidak menyertakan Roti Bakar Keju, Roti Bakar Coklat, dan Nasi Goreng Seafood.
-- Jika ketiga item itu sudah ada dari skrip lama, barisnya tidak dihapus di sini.
--
-- Nama yang sudah ada (termasuk ejaan Ayam Palleko / Beef Blackpepper) tidak didobel.
-- Kolom price (Normal) tidak diubah. Harga foto masuk ke harga_reguler.
-- Deskripsi disimpan di kolom description (baru, jika belum ada).

alter table public.menu_availability
  add column if not exists harga_reguler numeric,
  add column if not exists description text;

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

insert into public.menu_availability (
  category, name, price, harga_reguler, description, is_ready, stock_qty, sort_order
)
select v.category, v.name, null, v.harga_reguler, v.description, true, 0,
       (select coalesce(max(m.sort_order), 0) from public.menu_availability m) + v.n
from (values
  (1, 'Rice Bowl', 'Paru Rica', 35000,
      'Paru sapi goreng, sambal rica cabai rawit, kemangi.'),
  (2, 'Rice Bowl', 'Salted Egg Shrimp', 38000,
      'Udang crispy, saus telur asin, daun kari.'),
  (3, 'Rice Bowl', 'Salted Egg Chicken', 35000,
      'Ayam crispy, saus telur asin, daun kari.'),
  (4, 'Rice Bowl', 'Ayam Palekko', 35000,
      'Resep Bugis. Ayam cincang, cabai, asam mangga muda.'),
  (5, 'Rice Bowl', 'Beef Black Pepper', 40000,
      'Sapi tumis lada hitam, bawang bombay, paprika.'),
  (6, 'Nasi Goreng', 'Nasi Goreng Lokalin', 38000,
      'Signature. Ayam suwir, telur, sambal rumahan.'),
  (7, 'Indomie', 'Indomie Goreng Telur', 20000,
      'Telur mata sapi, bawang goreng, irisan cabai.'),
  (8, 'Indomie', 'Indomie Goreng Spesial', 28000,
      'Telur, kornet, keju, cabai rawit.')
) as v(n, category, name, harga_reguler, description)
where not exists (
  select 1 from public.menu_availability m
  where public.lokalin_menu_name_key(m.name) = public.lokalin_menu_name_key(v.name)
);

update public.menu_availability m
set harga_reguler = v.harga_reguler,
    description = v.description
from (values
  ('Paru Rica', 35000, 'Paru sapi goreng, sambal rica cabai rawit, kemangi.'),
  ('Salted Egg Shrimp', 38000, 'Udang crispy, saus telur asin, daun kari.'),
  ('Salted Egg Chicken', 35000, 'Ayam crispy, saus telur asin, daun kari.'),
  ('Ayam Palekko', 35000, 'Resep Bugis. Ayam cincang, cabai, asam mangga muda.'),
  ('Beef Black Pepper', 40000, 'Sapi tumis lada hitam, bawang bombay, paprika.'),
  ('Nasi Goreng Lokalin', 38000, 'Signature. Ayam suwir, telur, sambal rumahan.'),
  ('Indomie Goreng Telur', 20000, 'Telur mata sapi, bawang goreng, irisan cabai.'),
  ('Indomie Goreng Spesial', 28000, 'Telur, kornet, keju, cabai rawit.')
) as v(name, harga_reguler, description)
where public.lokalin_menu_name_key(m.name) = public.lokalin_menu_name_key(v.name);
