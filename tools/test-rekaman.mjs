// Uji jalur rekaman: IndexedDB + AudioContext dipalsukan.
let diputar = [], diucap = [];
const simpanan = new Map();

// --- palsu: IndexedDB ---
function fakeReq(result, err){
  const r = { result, error: err || null, onsuccess:null, onerror:null, onupgradeneeded:null };
  queueMicrotask(() => (err ? r.onerror && r.onerror() : r.onsuccess && r.onsuccess()));
  return r;
}
const store = {
  put: (v,k) => { simpanan.set(k,v); return fakeReq(true); },
  get: k => fakeReq(simpanan.get(k)),
  delete: k => { simpanan.delete(k); return fakeReq(true); },
};
global.indexedDB = {
  open: () => fakeReq({
    createObjectStore(){},
    transaction: () => ({ objectStore: () => store }),
  }),
};

// --- palsu: AudioContext ---
class FakeCtx {
  constructor(){ this.state='running'; this.destination={}; }
  resume(){ this.state='running'; return Promise.resolve(); }
  decodeAudioData(buf){ return Promise.resolve({ dur: buf.byteLength }); }
  createBufferSource(){
    return { buffer:null, connect(){}, onended:null,
             start(){ diputar.push(this.buffer.dur); queueMicrotask(()=>this.onended&&this.onended()); } };
  }
}
global.window = { AudioContext: FakeCtx };
global.Audio = class { constructor(s){ this.src=s; } play(){ setTimeout(()=>this.onerror&&this.onerror(),0); return Promise.resolve(); } };
global.SpeechSynthesisUtterance = class { constructor(t){ this.text=t; } };
const synth = { getVoices:()=>[{name:'Damayanti',lang:'id-ID',voiceURI:'id1'}],
  speak:u=>diucap.push(u.text), cancel(){}, resume(){}, speaking:false };
global.speechSynthesis = synth; window.speechSynthesis = synth;
global.localStorage = { getItem:()=>null, setItem(){} };

const M = await import('../suara-panggilan.js');

let gagal=0;
const cek=(n,d,h)=>{const ok=JSON.stringify(d)===JSON.stringify(h);if(!ok){gagal++;
  console.log(`FAIL  ${n}\n        dapat ${JSON.stringify(d)}\n        harap ${JSON.stringify(h)}`)}
  else console.log(`  ok  ${n}`)};

M.aktifkan();
diucap.length = 0;

const RUANG = 'Meeting Room Lantai 1';
cek('awalnya belum ada rekaman', await M.adaRekaman(RUANG), false);
cek('tanpa rekaman jatuh ke ucapan', await M.panggil(RUANG, {paksa:true}), 'ucapan');

// simpan rekaman palsu
const blob = { arrayBuffer: async () => new ArrayBuffer(321) };
cek('simpan rekaman', await M.simpanRekaman(RUANG, blob), true);
cek('rekaman terdeteksi', await M.adaRekaman(RUANG), true);

const n = diucap.length;
cek('rekaman dipakai', await M.panggil(RUANG, {paksa:true, ulang:2}), 'rekaman');
cek('tidak mengucap saat ada rekaman', diucap.length, n);
cek('diputar 2x', diputar.length, 2);
cek('buffer benar', diputar[0], 321);

// ruang lain tidak ikut terpengaruh
cek('ruang lain tetap ucapan', await M.panggil('Meeting Room Lantai 2', {paksa:true}), 'ucapan');

cek('hapus rekaman', await M.hapusRekaman(RUANG), true);
cek('setelah dihapus kembali ke ucapan', await M.panggil(RUANG, {paksa:true}), 'ucapan');

console.log(gagal ? `\n${gagal} uji GAGAL` : '\nsemua uji lulus');
process.exit(gagal?1:0);
