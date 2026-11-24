# Usulan harga Normal — November 2026

**Status: USULAN. Belum diterapkan.** Dokumen ini tidak mengubah harga di kasir, menu digital, atau Supabase. Penerapan hanya setelah pemilik menyetujui dan meminta merge/terapkan.

Sumber harga Normal saat ini: `public.pos_products` di proyek Supabase Lokalin-management, dibaca 24 November 2026 (WITA). Harga porsi Reguler (lantai, tidak boleh dilampaui ke bawah) dari `public.menu_availability.harga_reguler` dan kartu menu cetak.

## Prinsip

1. Minuman yang sudah kompetitif **tetap**.
2. Makanan yang jauh di atas kafe sejenis di area yang sama (terutama Roket Roastery, jalan yang sama) **disesuaikan**, dengan potongan yang perlu saja agar margin terjaga.
3. Pembulatan ke Rp1.000 terdekat.
4. Harga Normal usulan **tidak boleh lebih rendah** dari harga Reguler.
5. Tidak ada perubahan ke tabel atau halaman kasir pada PR ini.

## Ringkasan perubahan

Dari 45 item di `pos_products`, **5 item diusulkan turun**, **40 item tetap**.

| Menu | Sekarang | Usulan | Selisih | Lantai Reguler |
|---|---:|---:|---:|---:|
| Nasi Goreng Lokalin | 55.000 | 45.000 | −10.000 | 38.000 |
| Beef Blackpepper | 65.000 | 50.000 | −15.000 | 40.000 |
| Paru Rica | 50.000 | 45.000 | −5.000 | 35.000 |
| Pisang Goreng | 35.000 | 28.000 | −7.000 | — |
| Ubi Goreng | 32.000 | 28.000 | −4.000 | — |

## Usulan lengkap

### Makanan

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Nasi Goreng Lokalin | 55.000 | **45.000** | Roket (menu digital 2026, jalan yang sama) menjual nasi goreng 43.000. Usulan 45.000 mendekati itu, tetap 2.000 di atas sebagai signature, dan jauh di atas Reguler 38.000. |
| Mie Goreng Lokalin | 45.000 | 45.000 | Tetap, sudah kompetitif. Roket Mie Goreng Jawa 40.000; selisih tipis, potongan tidak perlu. |
| Ayam Goreng Rica | 50.000 | 50.000 | Tetap, sudah kompetitif. Hidangan utama khas; tidak ada padanan langsung di Roket. |

### Rice Bowl

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Ayam Palleko | 45.000 | 45.000 | Tetap, sudah kompetitif. Sejajar puncak rice bowl Roket (Buttermilk / Sambal Matah / Salted Egg / Nanban 45.000). Di atas Reguler 35.000. |
| Salted Egg Shrimp | 45.000 | 45.000 | Tetap, sudah kompetitif. Sejajar Salted Egg Roket 45.000; udang tidak perlu lebih murah dari ayam. Di atas Reguler 38.000. |
| Paru Rica | 50.000 | **45.000** | Disamakan dengan puncak rice bowl Roket 45.000 dan Ayam Palleko. Masih 10.000 di atas Reguler 35.000. |
| Beef Blackpepper | 65.000 | **50.000** | 65.000 jauh di atas kisaran rice bowl area (Roket 32.000–45.000). Usulan 50.000 tetap premi di atas bowl ayam 45.000 karena bahan sapi, dan di atas Reguler 40.000. |

### Snack

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Pisang Goreng | 35.000 | **28.000** | Tidak ada harga dine-in pisang goreng sejenis di kafe tetangga; acuan terdekat Roket Ubi Goreng 25.000 dan Kentang Goreng 35.000. Usulan 28.000 mendekati ubi Roket tanpa turun sampai 25.000 (margin). |
| Ubi Goreng | 32.000 | **28.000** | Roket Ubi Goreng 25.000. Usulan 28.000, sama dengan pisang, masih di atas acuan tetangga. |
| Chicken Wings | 35.000 | 35.000 | Tetap, sudah kompetitif. Roket Chicken Wings Spicy / Hongkong 35.000. |
| Crispy Wedges Potato | 30.000 | 30.000 | Tetap, sudah kompetitif. Di bawah Roket Kentang Goreng 35.000. |
| Potato Barbeque | 20.000 | 20.000 | Tetap, sudah kompetitif. Lebih murah dari kentang Roket. |
| Bakara | 35.000 | 35.000 | Tetap, sudah kompetitif. Sejajar camilan goreng Roket 25.000–35.000; tidak ada padanan nama yang sama. |
| Fried Chicken | 38.000 | 38.000 | Tetap, sudah kompetitif. Camilan ayam; tidak ada acuan identik, hindari potongan tanpa dasar. |
| Meat Fries | 45.000 | 45.000 | Tetap, sudah kompetitif. Camilan berbagi (loaded fries), bukan kentang biasa. |
| Sanggara Balanda | 25.000 | 25.000 | Tetap, sudah kompetitif. Kue lokal, tidak ada tekanan harga dari tetangga. |

### Burger & Sandwich

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Crispy Chicken Sandwich | 50.000 | 50.000 | Tetap, sudah kompetitif. Sejajar pasta/hidangan utama menengah Roket (45.000–50.000). |
| The Cheese Melt Burger | 45.000 | 45.000 | Tetap, sudah kompetitif. |

### Roti Kukus

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Roti Kukus Srikaya | 30.000 | 30.000 | Tetap, sudah kompetitif. Tidak ada padanan langsung; hindari potongan tanpa dasar. |
| Roti Kukus Coklat | 30.000 | 30.000 | Tetap, sudah kompetitif. |
| Roti Kukus Greentea | 30.000 | 30.000 | Tetap, sudah kompetitif. |

### Coffee Classic

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Americano | 25.000 | 25.000 | Tetap, sudah kompetitif. Roket 28.000; Fore 23.000. |
| Coffee Latte | 28.000 | 28.000 | Tetap, sudah kompetitif. Roket Ice Coffee Latte 31.000; Fore Café Latte 29.000. |
| Cappuccino | 28.000 | 28.000 | Tetap, sudah kompetitif. Roket 31.000. |
| Cold Sweet Coffee | 30.000 | 30.000 | Tetap, sudah kompetitif. Di bawah signature tetangga (Roket 30.000–40.000). |
| Caramel Coffee | 30.000 | 30.000 | Tetap, sudah kompetitif. Roket Caramel Macchiato 32.000–37.000. |
| Hazelnut Coffee | 30.000 | 30.000 | Tetap, sudah kompetitif. |
| Vanilla Coffee | 30.000 | 30.000 | Tetap, sudah kompetitif. Roket Ice Vanilla Latte 32.000–37.000. |
| Mocha | 32.000 | 32.000 | Tetap, sudah kompetitif. |

### Coffee & Mocktail (Signature)

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Coffee Lokalin | 40.000 | 40.000 | Tetap, sudah kompetitif. Sejajar Roket Butterscotch Dynamite 40.000. Di atas No Limit (kisaran minuman 15.000–30.000), tetapi setara signature kafe sejenis di jalan yang sama. |
| Pandan Coffee | 35.000 | 35.000 | Tetap, sudah kompetitif. Sejajar Aren Latte Roket 30.000–35.000. |
| Salted Caramel Coffee | 35.000 | 35.000 | Tetap, sudah kompetitif. |
| Signature Coffee | 35.000 | 35.000 | Tetap, sudah kompetitif. |
| Butterscotch Coffee | 35.000 | 35.000 | Tetap, sudah kompetitif. Roket Butterscotch Latte 34.000–37.000. |
| Tropical Citrus | 35.000 | 35.000 | Tetap, sudah kompetitif. Mocktail, tidak ada tekanan harga. |
| Summer Paradise | 35.000 | 35.000 | Tetap, sudah kompetitif. |

### Tea

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Tea | 15.000 | 15.000 | Tetap, sudah kompetitif (lebih murah). Roket Hot Black Tea 29.000; Excelso Classic Ice Tea 42.000. |
| Thai Tea | 25.000 | 25.000 | Tetap, sudah kompetitif. |
| Lemon Tea | 25.000 | 25.000 | Tetap, sudah kompetitif. Di bawah Roket Peach Tea 29.000–34.000. |
| Peach Tea | 25.000 | 25.000 | Tetap, sudah kompetitif. Roket Peach Tea 29.000–34.000. |
| Markisa | 25.000 | 25.000 | Tetap, sudah kompetitif. |

### Non Coffee

| Menu | Sekarang | Usulan | Alasan |
|---|---:|---:|---|
| Chocolate | 30.000 | 30.000 | Tetap, sudah kompetitif. Roket Chocolate 29.000–34.000. |
| Red Velvet | 30.000 | 30.000 | Tetap, sudah kompetitif. |
| Green Tea | 30.000 | 30.000 | Tetap, sudah kompetitif. |
| Ice Milo | 25.000 | 25.000 | Tetap, sudah kompetitif. Fore Classic Milo 25.000. |

## Catatan

- Setelah usulan ini, Nasi Goreng Normal 45.000 masih di atas kartu Reguler 38.000. Kesenjangan itu disengaja (porsi/harga beda), tetapi lebih masuk akal daripada 55.000 vs 38.000.
- Item di `menu_availability` yang **tidak** ada di kasir `pos_products` (Indomie Goreng Telur, Indomie Goreng Spesial, Salted Egg Chicken) tidak diusulkan di sini.
- Harga aplikasi pesan-antar biasanya sekitar 20–30% di atas dine-in dan **bukan** acuan usulan ini. (Contoh: Nasi Goreng di Grab 66.000 vs Normal dine-in sekarang 55.000.)
- File pendamping: [`docs/usulan-harga-normal-2026-11.csv`](usulan-harga-normal-2026-11.csv) (`product_id,name,current,proposed`).

## Sumber acuan dine-in

- Roket Roastery (Jl. Prof. Abdurahman Basalamah / Racing Centre), *Digital Menu / 2026*, PDF resmi 27 Maret 2026: <https://roketroastery.com/menu.pdf> dan <https://roketroastery.com/menu>
- No Limit Coffee Racing, pernyataan owner bahwa harga minuman Rp15.000–Rp30.000, 4 Juli 2025: <https://rakyatsulsel.fajar.co.id/2025/07/04/cafe-no-limit-buka-cabang-ketiga-di-jalan-hertasning/>
- Fore Coffee, harga dikutip dari situs resmi, 16 November 2026: <https://kumparan.com/kabar-harian/harga-kopi-fore-untuk-para-pencinta-kopi-28ZxJfrOX1Q>
- Excelso, daftar menu Februari 2026 (acuan plafon kafe mal, bukan tetangga langsung): <https://blog.ultravoucher.co.id/menu-excelso-coffee/>
