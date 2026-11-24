// Logika skor & potongan Penilaian Kinerja (murni, tanpa DOM/Supabase) — dipakai penilaian.html dan payroll.html
export const DEFAULT_CFG = {potongan_telat_ringan: 5000, potongan_telat_berat: 10000, potongan_tidak_update_stok: 5000, hangus_di_bawah: 60};
export const SHIFT_START = {pagi: 600, sore: 960};
const BULAN_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

export const clamp = (v, max) => Math.max(0, Math.min(max, Number(v) || 0));

// Bulan kalender YYYY-MM: tanggal 1 sampai hari terakhir.
export function monthRange(m){
  if (!BULAN_RE.test(m)) throw Error('Pilih bulan penilaian');
  const [y, mo] = m.split('-').map(Number);
  return {m, start: m + '-01', end: m + '-' + String(new Date(Date.UTC(y, mo, 0)).getUTCDate()).padStart(2, '0')};
}

export function minutes(t){
  const m = /^(\d{1,2}):(\d{2})/.exec(String(t || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

// e = {id, name}; att = baris absensi_harian; monthly = {emp_id: baris penilaian_bulanan}
// tel = {emp_id: {hadir, ringan, berat}} hasil RPC lokalin_penilaian_telat; bila ada, dipakai menggantikan att.
export function kehadiran(e, att, monthly, tel){
  if (tel){
    const t = tel[e.id] || {}, n = v => Math.max(0, Math.floor(Number(v) || 0));
    const ringan = n(t.ringan), berat = n(t.berat);
    return {hadir: n(t.hadir), ringan, berat, poin: Math.max(0, 30 - ringan * 2 - berat * 5)};
  }
  const rows = att.filter(r => r.jam_masuk && (r.emp_id ? String(r.emp_id) === e.id : String(r.nama || '').trim().toLowerCase() === e.name.trim().toLowerCase()));
  rows.sort((a, b) => a.tanggal.localeCompare(b.tanggal) || String(a.jam_masuk).localeCompare(String(b.jam_masuk)));
  const seen = new Set();
  let ringan = 0, berat = 0, hadir = 0;
  for (const r of rows){
    if (seen.has(r.tanggal)) continue;
    seen.add(r.tanggal); hadir++;
    const start = SHIFT_START[String(r.shift || '').trim().toLowerCase()], mi = minutes(r.jam_masuk);
    if (start == null || mi == null) continue;
    const late = mi - start;
    if (late >= 1 && late <= 15) ringan++; else if (late > 15) berat++;
  }
  return {hadir, ringan, berat, poin: Math.max(0, 30 - ringan * 2 - berat * 5)};
}

export function kualitas(e, weekly){
  const w = weekly.filter(r => r.emp_id === e.id);
  if (!w.length) return null;
  const avg = w.reduce((a, r) => a + (r.kebersihan + r.sop_resep + r.kecepatan) / 3, 0) / w.length;
  return Math.round(avg / 5 * 25 * 10) / 10;
}

export function tier(total, viol){
  if (total >= 90) return {label: 'Kandidat Staf Terbaik', bonus: 150000};
  if (total >= 75) return {label: 'Baik', bonus: viol ? 0 : 100000, note: viol ? 'Ada pelanggaran, tanpa bonus' : ''};
  if (total >= 60) return {label: 'Pembinaan', bonus: 0};
  return {label: 'Jalur SP', bonus: 0};
}

// d = {att, weekly, monthly, cfg, tel}
export function hitung(e, {att, weekly, monthly, cfg, tel}){
  const k = kehadiran(e, att, monthly, tel), q = kualitas(e, weekly), m = monthly[e.id] || {};
  const pel = clamp(m.pelayanan ?? 20, 20), sik = m.sikap == null ? null : clamp(m.sikap, 15), ini = m.inisiatif == null ? null : clamp(m.inisiatif, 10), viol = !!m.ada_pelanggaran;
  const stok = Math.max(0, Math.floor(Number(m.tidak_update_stok) || 0));
  // Tidak update stok saat shift: -3 poin per kali, total tidak turun di bawah 0.
  const total = Math.max(0, Math.round((k.poin + (q || 0) + pel + (sik || 0) + (ini || 0) - stok * 3) * 10) / 10);
  const t = tier(total, viol), hangus = total < cfg.hangus_di_bawah || (total >= 75 && total < 90 && viol);
  const potongan = Math.max(0, k.ringan * cfg.potongan_telat_ringan + k.berat * cfg.potongan_telat_berat + stok * (Number(cfg.potongan_tidak_update_stok) || 0));
  return {k, q, pel, sik, ini, viol, stok, total, t, hangus, potongan};
}
