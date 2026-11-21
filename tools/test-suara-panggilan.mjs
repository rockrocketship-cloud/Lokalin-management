// Uji logika suara-panggilan.js tanpa browser.
let diucap = [], diputar = [], adaKlip = new Set();

class FakeAudio {
  constructor(src){ this.src = src; this.currentTime = 0; }
  play(){
    if(adaKlip.has(this.src)){ diputar.push(this.src); setTimeout(()=>this.onended&&this.onended(),0); return Promise.resolve(); }
    setTimeout(()=>this.onerror&&this.onerror(),0);
    return Promise.resolve();
  }
}
global.window = {};
global.Audio = FakeAudio;
global.SpeechSynthesisUtterance = class { constructor(t){ this.text = t; } };
const synth = {
  getVoices: () => [{name:'Damayanti', lang:'id-ID'}],
  speak: u => { if(u.volume !== 0) diucap.push(u.text); },
  cancel: () => {},
};
global.speechSynthesis = synth; window.speechSynthesis = synth;

const M = await import('../suara-panggilan.js');

let gagal = 0;
const cek = (nama, dapat, harap) => {
  const ok = JSON.stringify(dapat) === JSON.stringify(harap);
  if(!ok){ gagal++; console.log(`FAIL  ${nama}\n        dapat ${JSON.stringify(dapat)}\n        harap ${JSON.stringify(harap)}`); }
  else console.log(`  ok  ${nama}`);
};

// 1. sebelum aktifkan() -> diam (belum ada gestur pengguna)
cek('sebelum aktifkan: diam', await M.panggil('Meeting Room Lantai 1'), 'diam');
cek('belum aktif', M.aktif(), false);

// 2. setelah aktifkan() -> mengucapkan
cek('aktifkan() berhasil', M.aktifkan(), true);
cek('aktif', M.aktif(), true);
cek('suara id-ID terpilih', M.suara(), 'Damayanti');
cek('ucapan dipakai', await M.panggil('Meeting Room Lantai 1'), 'ucapan');
cek('teks benar', diucap.at(-1), 'Panggilan dari Meeting Room Lantai 1');
cek('diulang 2x', diucap.filter(t=>t.includes('Lantai 1')).length, 2);

// 3. panggilan ulang ruang sama dalam 20s -> dilewati (anti-spam)
cek('ruang sama: dilewati', await M.panggil('Meeting Room Lantai 1'), 'dilewati');
cek('paksa menembus jeda', await M.panggil('Meeting Room Lantai 1',{paksa:true,ulang:1}), 'ucapan');

// 4. ruang berbeda tidak terkena jeda
cek('ruang lain tetap diumumkan', await M.panggil('Meeting Room Lantai 2'), 'ucapan');

// 5. klip ada -> klip dipakai, tidak mengucap
adaKlip.add('./audio/panggilan-meeting-room-lantai-3.wav');
const n = diucap.length;
cek('klip dipakai bila ada', await M.panggil('Meeting Room Lantai 3'), 'klip');
cek('klip dipakai, ucapan diam', diucap.length, n);

// 6. perangkat tanpa Web Speech -> diam, bukan error
delete window.speechSynthesis;
cek('tanpa Web Speech: diam', await M.panggil('Meeting Room Lantai 9'), 'diam');

console.log(gagal ? `\n${gagal} uji GAGAL` : '\nsemua uji lulus');
process.exit(gagal ? 1 : 0);
