// Logika slip gaji WA Lokalin (murni, tanpa DOM/Supabase) — dipakai payroll.html dan dites di tools/test-payroll-slip.mjs
const BULAN = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
const PERIODE_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

export function normalizeWa(raw){
  let d = String(raw ?? '').replace(/\D/g, '');
  if (d.startsWith('0')) d = '62' + d.slice(1);
  else if (d.startsWith('8')) d = '62' + d;
  return /^62\d{8,13}$/.test(d) ? d : null;
}

export function rupiah(n){
  const v = Math.round(Number(n) || 0);
  const s = String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return (v < 0 ? '-' : '') + 'Rp' + s;
}

export function periodeLabel(month){
  const [y, m] = month.split('-').map(Number);
  const py = m === 1 ? y - 1 : y, pm = m === 1 ? 12 : m - 1;
  const awal = `26 ${BULAN[pm - 1]}` + (py !== y ? ` ${py}` : '');
  return `${awal} – 25 ${BULAN[m - 1]} ${y}`;
}

export function formatSlip({periodeLabel, name, position, days, rate, meal, bonus, deduct}){
  const shift = days * rate, makan = days * meal, total = shift + makan + bonus - deduct;
  return [
    'SLIP GAJI – LOKALIN CAFE',
    `Periode: ${periodeLabel}`,
    `Nama: ${name}${position ? ` (${position})` : ''}`,
    '',
    `Shift      : ${days} × ${rupiah(rate)} = ${rupiah(shift)}`,
    `Uang makan : ${days} × ${rupiah(meal)} = ${rupiah(makan)}`,
    `Bonus      : ${rupiah(bonus)}`,
    `Potongan   : ${rupiah(deduct)}`,
    '-------------------------',
    `TOTAL      : ${rupiah(total)}`,
    '',
    'Terima kasih atas kerja kerasnya 🙏',
  ].join('\n');
}

export function waLink(noWa, text){
  const n = normalizeWa(noWa);
  return n ? `https://wa.me/${n}?text=${encodeURIComponent(text)}` : null;
}

const angka = x => Math.max(0, Math.min(1000000000, Math.round(Number(x) || 0)));

// local: {"2026-11|id:…": {rate,meal,bonus,deduct}} dari localStorage lama; remoteKeys: Set "periode|emp_key" yang sudah ada di Supabase
export function planMigration(local, remoteKeys){
  const rows = [];
  for (const [k, v] of Object.entries(local || {})) {
    const i = k.indexOf('|');
    if (i < 0 || remoteKeys.has(k) || !v || typeof v !== 'object') continue;
    const periode = k.slice(0, i), emp_key = k.slice(i + 1);
    if (!PERIODE_RE.test(periode) || !emp_key) continue;
    rows.push({periode, emp_key, rate: v.rate == null ? null : angka(v.rate), meal: angka(v.meal), bonus: angka(v.bonus), deduct: angka(v.deduct)});
  }
  return rows;
}
