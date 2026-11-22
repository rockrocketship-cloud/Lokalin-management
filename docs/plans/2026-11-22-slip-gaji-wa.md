# Rencana: Slip Gaji via WA — Lokalin Cafe

**Tujuan:** owner mengirim slip gaji per staf reguler lewat WhatsApp (tombol wa.me) dari `payroll.html`, dengan penyesuaian gaji tersimpan di Supabase.

**Arsitektur:** halaman statis (GitHub Pages) + Supabase (`kwhtqqrzeifmntdtugvg`). Logika murni dipisah ke `payroll-slip.js` (bisa dites di Node tanpa browser); `payroll.html` hanya UI + panggilan Supabase.

**Tech stack:** HTML + JS modul, supabase-js (sudah dipakai), Postgres + RLS, tes Node 22 (`node tools/test-payroll-slip.mjs`, gaya sama dengan `tools/test-suara-panggilan.mjs`).

**Desain:** disetujui di chat 22 Nov 2026.

## Batasan Global
- Hanya 6 staf reguler. DW, pajak/BPJS, pembayaran otomatis, kirim otomatis: di luar cakupan.
- Rumus gaji tidak berubah: `shift × (tarif + uang makan) + bonus − potongan`, periode 26 bulan lalu s.d. 25 bulan ini (WITA), maksimal 1 shift per orang per tanggal.
- Data gaji & nomor WA hanya bisa dibaca/diubah role `owner` (`app_roles`).
- Kirim = membuka `https://wa.me/<nomor>?text=<pesan>`; owner menekan kirim sendiri.

## ⚠️ Penyimpangan dari desain (keputusan saya, mohon cek)
Desain menaruh `no_wa` di tabel `employees`. Tapi `employees` bisa dibaca akun **kiosk** (HP absensi di cafe), jadi nomor WA staf akan ikut terlihat di sana. Karena itu nomor WA disimpan di tabel owner-only `payroll_contacts`. Hasil untuk owner sama persis.

## Fokus Review
1. Nomor WA format lokal (`0812…`, `+62 812-…`, `62812…`) → harus jadi `62812…`; nomor kosong/terlalu pendek → tombol nonaktif.
2. Angka Rupiah di pesan: pemisah titik, tanpa desimal, potongan 0 tetap tampil.
3. Pesan dengan karakter khusus (`&`, `#`, baris baru, emoji) harus utuh setelah di-encode ke URL.
4. Migrasi data lama dari `localStorage` hanya sekali dan tidak menimpa data yang sudah ada di Supabase.
5. Akun non-owner (kiosk) tidak bisa membaca `payroll_adjustments` / `payroll_contacts`.

## Tugas 1 — Tabel Supabase
**Migration:** `payroll_slip_tables`
- `payroll_contacts(emp_id uuid PK → employees.id, no_wa text, updated_at timestamptz default now())`
- `payroll_adjustments(id uuid PK default gen_random_uuid(), periode text check (periode ~ '^\d{4}-(0[1-9]|1[0-2])$'), emp_key text not null, rate int, meal int default 0, bonus int default 0, deduct int default 0, catatan text, sent_at timestamptz, updated_at timestamptz default now(), unique(periode, emp_key))`
  - `emp_key` = `keyFor()` yang sudah ada (`id:<uuid>` atau `nama:<nama>`), `periode` = nilai input `month`.
- RLS aktif di keduanya; policy select/insert/update/delete: `exists(select 1 from app_roles r where r.user_id=(select auth.uid()) and r.role='owner')`.

**Tes (SQL):** sebagai role `authenticated` tanpa baris owner, `select` mengembalikan 0 baris & `insert` ditolak (Fokus 5). Jalankan dulu sebelum migration → gagal (tabel belum ada), sesudahnya → lulus. Cek juga `get_advisors` keamanan bersih.

## Tugas 2 — `payroll-slip.js` (logika murni)
**Buat:** `payroll-slip.js`, **tes:** `tools/test-payroll-slip.mjs`
Ekspor:
- `normalizeWa(raw:string) → string|null` — buang non-digit, `0…`→`62…`, `8…`→`628…`; valid jika 10–15 digit diawali `62`, selain itu `null`. (Fokus 1)
- `rupiah(n:number) → string` — `"Rp1.384.608"`. (Fokus 2)
- `formatSlip({periodeLabel, name, position, days, rate, meal, bonus, deduct}) → string` — teks persis seperti contoh di desain; total = rumus Batasan Global.
- `waLink(noWa:string, text:string) → string|null` — `null` jika `normalizeWa` null; selain itu `https://wa.me/${nomor}?text=${encodeURIComponent(text)}`. (Fokus 3)
- `planMigration(local:object, remoteKeys:Set<string>) → Array<row>` — ubah `{"2026-11|id:…": {rate,meal,bonus,deduct}}` jadi baris; lewati kunci yang sudah ada di remote. (Fokus 4)

Langkah: tulis tes untuk tiap fungsi (termasuk kasus Fokus 1–4) → jalankan, pastikan gagal → implementasi → lulus → commit `Tambah logika slip gaji WA + tes`.

## Tugas 3 — Simpan penyesuaian ke Supabase
**Ubah:** `payroll.html`
- `load()`: ambil `payroll_adjustments` (filter `periode`) dan `payroll_contacts`, isi `adjust` dari Supabase, bukan `localStorage`.
- Input di `staffRows`: simpan dengan `upsert(..., {onConflict:'periode,emp_key'})`, debounce 600 ms; status "Tersimpan ✓" / pesan error.
- Sekali per perangkat: baca `localStorage['lokalin_payroll_adjustments_v1']`, `planMigration`, insert hasilnya, lalu set `lokalin_payroll_migrated_v1=1`. Data lokal tidak dihapus (cadangan).
- Ganti catatan "disimpan hanya pada browser" dengan "tersimpan di Supabase".

**Tes:** manual di browser sebagai owner — ubah bonus, muat ulang dari perangkat/jendela privat lain → angka sama. Commit.

## Tugas 4 — Nomor WA + tombol Kirim WA
**Ubah:** `payroll.html`
- Kolom baru di tabel staf: input nomor WA (upsert ke `payroll_contacts`, divalidasi `normalizeWa`, merah jika tidak valid) dan tombol **📲 Kirim WA**.
- Tombol nonaktif jika `waLink` null atau `emp_key` bukan `id:` (staf tanpa id tidak bisa punya kontak).
- Klik: `window.open(waLink(...))`, lalu `upsert` `sent_at=now()`; tampilkan "Terkirim ✓ 22 Nov" dari `sent_at`.
- Label periode di slip memakai `period()` yang sudah ada, format "26 Okt – 25 Nov 2026".

**Tes:** manual — nomor `0812-3456-7890` → link `https://wa.me/6281234567890?text=…` membuka WA dengan pesan utuh; nomor kosong → tombol abu-abu. Commit.

## Tugas 5 — Verifikasi akhir
- `node tools/test-payroll-slip.mjs` lulus; `get_advisors` (security) tanpa temuan baru.
- Total di slip = total di tabel rekap untuk tiap staf.
- Buka sebagai akun kiosk → payroll tetap menolak akses.
- Push ke `main` (GitHub Pages) **setelah owner setuju**.
