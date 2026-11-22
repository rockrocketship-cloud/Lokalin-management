// Uji logika payroll-slip.js tanpa browser: node tools/test-payroll-slip.mjs
import assert from 'node:assert/strict';
import {normalizeWa, rupiah, formatSlip, waLink, planMigration, periodeLabel} from '../payroll-slip.js';

let lulus = 0;
const uji = (nama, fn) => { fn(); lulus++; console.log('✓', nama); };

uji('normalizeWa: format lokal jadi 62…', () => {
  assert.equal(normalizeWa('0812-3456-7890'), '6281234567890');
  assert.equal(normalizeWa('+62 812 3456 7890'), '6281234567890');
  assert.equal(normalizeWa('6281234567890'), '6281234567890');
  assert.equal(normalizeWa('81234567890'), '6281234567890');
});
uji('normalizeWa: kosong / pendek / aneh jadi null', () => {
  for (const x of ['', null, undefined, '0812', '12345678901', 'abc', '62' + '9'.repeat(20)]) assert.equal(normalizeWa(x), null, String(x));
});
uji('rupiah: titik ribuan, tanpa desimal', () => {
  assert.equal(rupiah(1384608), 'Rp1.384.608');
  assert.equal(rupiah(0), 'Rp0');
  assert.equal(rupiah(999.6), 'Rp1.000');
  assert.equal(rupiah(-50000), '-Rp50.000');
});
uji('periodeLabel: 26 bulan lalu – 25 bulan ini', () => {
  assert.equal(periodeLabel('2026-11'), '26 Okt – 25 Nov 2026');
  assert.equal(periodeLabel('2027-01'), '26 Des 2026 – 25 Jan 2027');
});
const contoh = {periodeLabel: '26 Okt – 25 Nov 2026', name: 'Lilis', position: 'Barista', days: 24, rate: 57692, meal: 10000, bonus: 100000, deduct: 50000};
uji('formatSlip: isi sesuai desain dan total benar', () => {
  const t = formatSlip(contoh);
  assert.ok(t.startsWith('SLIP GAJI – LOKALIN CAFE\nPeriode: 26 Okt – 25 Nov 2026\nNama: Lilis (Barista)'));
  assert.ok(t.includes('Shift      : 24 × Rp57.692 = Rp1.384.608'));
  assert.ok(t.includes('Uang makan : 24 × Rp10.000 = Rp240.000'));
  assert.ok(t.includes('Bonus      : Rp100.000'));
  assert.ok(t.includes('Potongan   : Rp50.000'));
  assert.ok(t.includes('TOTAL      : Rp1.674.608'));
});
uji('formatSlip: potongan 0 tetap tampil, jabatan kosong tanpa kurung', () => {
  const t = formatSlip({...contoh, deduct: 0, bonus: 0, position: ''});
  assert.ok(t.includes('Potongan   : Rp0'));
  assert.ok(t.includes('Nama: Lilis\n'));
});
uji('waLink: pesan karakter khusus utuh setelah decode', () => {
  const pesan = 'A & B #1\nbaris 2 🙏 100%?';
  const link = waLink('0812-3456-7890', pesan);
  assert.ok(link.startsWith('https://wa.me/6281234567890?text='));
  assert.equal(decodeURIComponent(link.split('?text=')[1]), pesan);
  assert.equal(waLink('', pesan), null);
});
uji('planMigration: ubah data lokal, lewati yang sudah ada di Supabase', () => {
  const local = {
    '2026-11|id:aaa': {rate: 57692, meal: 10000, bonus: 5000, deduct: 0},
    '2026-11|id:bbb': {rate: 1, meal: 1, bonus: 1, deduct: 1},
    '2026-10|nama:x|y': {rate: '60000', meal: -5},
    'rusak': {rate: 1},
    '2026-13|id:ccc': {rate: 1},
  };
  const rows = planMigration(local, new Set(['2026-11|id:bbb']));
  assert.deepEqual(rows, [
    {periode: '2026-11', emp_key: 'id:aaa', rate: 57692, meal: 10000, bonus: 5000, deduct: 0},
    {periode: '2026-10', emp_key: 'nama:x|y', rate: 60000, meal: 0, bonus: 0, deduct: 0},
  ]);
  assert.deepEqual(planMigration(null, new Set()), []);
});
console.log(`\n${lulus} tes lulus`);
