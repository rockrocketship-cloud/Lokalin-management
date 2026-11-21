// suara-panggilan.js — pengumuman suara untuk panggilan room service.
//
// Bel saja hanya memberi tahu "ada panggilan"; server masih harus melihat
// iPad untuk tahu ruang mana. Modul ini menyebutkan ruangnya, jadi server
// bisa langsung jalan tanpa menoleh ke layar.
//
// Dua jalur, dipilih otomatis:
//   1. klip .wav/.mp3 di audio/  (mis. audio/panggilan-lantai-1.wav)
//   2. Web Speech API bawaan perangkat, suara id-ID
//
// Pemakaian:
//   import {aktifkan, panggil, aktif} from './suara-panggilan.js';
//   tombol.onclick = () => { aktifkan(); };          // sekali, perlu gestur
//   panggil('Meeting Room Lantai 1');

const BASE = './audio';
const EXT = '.wav';
const ULANG = 2;            // berapa kali diucapkan; cafe berisik
const JEDA_SAMA = 20000;    // jangan ulangi ruang yang sama dalam 20 detik

const slug = s => String(s).normalize('NFKD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const KUNCI_SUARA = 'lokalin.suara.voiceURI';
const KUNCI_LAJU = 'lokalin.suara.rate';

let diizinkan = false;
let suaraID = null;
let laju = 0.95;              // sedikit lebih lambat, lebih jelas
const terakhir = new Map();   // slug ruang -> timestamp

// localStorage bisa tidak tersedia (mode privat, izin ditolak): jangan sampai
// itu mematikan pengumuman.
function simpanan(kunci, nilai) {
  try {
    if (nilai === undefined) return localStorage.getItem(kunci);
    localStorage.setItem(kunci, nilai);
  } catch (_) {}
  return null;
}

const skorSuara = v => {
  const t = ((v.name || '') + ' ' + (v.voiceURI || '')).toLowerCase();
  // iOS menyediakan Damayanti dalam beberapa mutu; yang premium jauh lebih
  // enak didengar, jadi pilih otomatis kalau sudah diunduh.
  if (t.includes('premium')) return 3;
  if (t.includes('enhanced')) return 2;
  return 1;
};

/** Semua suara perangkat, yang Bahasa Indonesia didahulukan. */
export function daftarSuara() {
  if (!('speechSynthesis' in window)) return [];
  const v = speechSynthesis.getVoices();
  const id = v.filter(x => x.lang && x.lang.toLowerCase().startsWith('id'))
              .sort((a, b) => skorSuara(b) - skorSuara(a));
  const lain = v.filter(x => !id.includes(x));
  return [...id, ...lain];
}

function pilihSuaraID() {
  if (!('speechSynthesis' in window)) return;
  const semua = speechSynthesis.getVoices();
  const tersimpan = simpanan(KUNCI_SUARA);
  suaraID = (tersimpan && semua.find(x => x.voiceURI === tersimpan))
         || daftarSuara().find(x => x.lang && x.lang.toLowerCase().startsWith('id'))
         || null;
  const r = parseFloat(simpanan(KUNCI_LAJU));
  if (r >= 0.5 && r <= 1.5) laju = r;
}

/** Pilih suara lain; diingat di perangkat ini. */
export function setSuara(voiceURI) {
  const v = daftarSuara().find(x => x.voiceURI === voiceURI);
  if (!v) return false;
  suaraID = v;
  simpanan(KUNCI_SUARA, voiceURI);
  return true;
}

/** Atur kecepatan bicara (0.5–1.5); diingat di perangkat ini. */
export function setKecepatan(r) {
  r = parseFloat(r);
  if (!(r >= 0.5 && r <= 1.5)) return false;
  laju = r;
  simpanan(KUNCI_LAJU, String(r));
  return true;
}

/** Kecepatan yang sedang dipakai. */
export function kecepatan() { return laju; }

/** voiceURI suara yang sedang dipakai, atau null. */
export function suaraURI() { return suaraID ? suaraID.voiceURI : null; }
if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
  pilihSuaraID();
  speechSynthesis.onvoiceschanged = pilihSuaraID;
}

/**
 * Panggil dari dalam handler klik — iOS/Safari memblokir audio yang tidak
 * dipicu gestur pengguna. Aman dipanggil berulang.
 * @returns {boolean} apakah perangkat ini mendukung suara ucapan
 */
export function aktifkan() {
  diizinkan = true;
  if (!('speechSynthesis' in window)) return false;
  try {
    pilihSuaraID();
    // Jangan pakai utterance volume 0 sebagai pembuka: di Safari iOS volume
    // nol bisa "nyangkut" dan membuat semua ucapan berikutnya bisu. Satu kata
    // pendek bervolume normal membuka izinnya tanpa efek samping itu.
    const u = new SpeechSynthesisUtterance('Siap');
    u.lang = 'id-ID';
    if (suaraID) u.voice = suaraID;
    speechSynthesis.speak(u);
    mulaiJagaHidup();
    // Dibuat di dalam ketukan supaya langsung berstatus 'running'.
    try {
      ctx ??= new (window.AudioContext || window.webkitAudioContext)();
      ctx.resume();
    } catch (_) {}
  } catch (_) {
    return false;
  }
  return true;
}

// Safari dan Chrome sama-sama bisa menidurkan mesin ucapan pada halaman yang
// dibiarkan terbuka lama — persis cara iPad kasir dipakai. resume() berkala
// menjaganya tetap siap; tanpa ini panggilan sore hari bisa bisu padahal
// pagi tadi normal.
let jagaHidup = null;
function mulaiJagaHidup() {
  if (jagaHidup || !('speechSynthesis' in window)) return;
  jagaHidup = setInterval(() => {
    try {
      if (!speechSynthesis.speaking) speechSynthesis.resume();
    } catch (_) {}
  }, 10000);
}

/** Apakah pengumuman suara sudah diizinkan dan didukung. */
export function aktif() {
  return diizinkan && 'speechSynthesis' in window;
}

/** Nama suara id-ID yang dipakai, atau null kalau perangkat tidak punya. */
export function suara() {
  return suaraID ? suaraID.name : null;
}

function ucap(teks, kali) {
  if (!('speechSynthesis' in window)) return false;
  try {
    // Daftar suara kadang baru terisi setelah halaman berjalan beberapa saat.
    if (!suaraID) pilihSuaraID();
    // resume() terpisah: di browser yang tidak punya atau menolaknya, ucapan
    // tetap harus jalan.
    try { speechSynthesis.resume(); } catch (_) {}
    for (let i = 0; i < kali; i++) {
      const u = new SpeechSynthesisUtterance(teks);
      u.lang = 'id-ID';
      if (suaraID) u.voice = suaraID;
      u.rate = laju;
      speechSynthesis.speak(u);          // antre, tidak saling memotong
    }
    return true;
  } catch (_) {
    return false;
  }
}

// --- Rekaman sendiri -------------------------------------------------------
//
// Jalur paling andal di Safari iOS. Ucapan Web Speech sering bisu pada halaman
// yang dibiarkan terbuka lama, sedangkan AudioContext yang sudah dibuka oleh
// satu ketukan tetap bisa memutar suara berjam-jam sesudahnya — persis cara
// bel di halaman ini bekerja. Jadi pengumuman direkam sekali dengan suara
// manusia, lalu diputar lewat context yang sama.

const DB = 'lokalin-suara', TOKO = 'rekaman';
let ctx = null;

function buka() {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(TOKO);
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}

function transaksi(mode, fn) {
  return buka().then(db => new Promise((resolve, reject) => {
    const t = db.transaction(TOKO, mode);
    const permintaan = fn(t.objectStore(TOKO));
    permintaan.onsuccess = () => resolve(permintaan.result);
    permintaan.onerror = () => reject(permintaan.error);
  }));
}

/** Simpan rekaman pengumuman untuk satu ruang. */
export async function simpanRekaman(ruang, blob) {
  const buf = await blob.arrayBuffer();
  await transaksi('readwrite', t => t.put(buf, slug(ruang)));
  return true;
}

/** Hapus rekaman satu ruang. */
export async function hapusRekaman(ruang) {
  await transaksi('readwrite', t => t.delete(slug(ruang)));
  return true;
}

/** ArrayBuffer rekaman, atau null. */
export async function ambilRekaman(ruang) {
  try {
    return (await transaksi('readonly', t => t.get(slug(ruang)))) || null;
  } catch (_) {
    return null;
  }
}

/** Apakah ruang ini sudah punya rekaman. */
export async function adaRekaman(ruang) {
  return (await ambilRekaman(ruang)) !== null;
}

// Diputar lewat AudioContext, bukan <audio>: context yang dibuka saat ketukan
// tetap berbunyi untuk kejadian yang datang jauh sesudahnya.
async function putarBuffer(arrayBuffer, kali) {
  if (!ctx) throw new Error('audio belum diaktifkan');
  if (ctx.state === 'suspended') await ctx.resume();
  // decodeAudioData merusak buffer aslinya, jadi salin dulu tiap pemutaran.
  const audio = await ctx.decodeAudioData(arrayBuffer.slice(0));
  for (let i = 0; i < kali; i++) {
    await new Promise(resolve => {
      const src = ctx.createBufferSource();
      src.buffer = audio;
      src.connect(ctx.destination);
      src.onended = resolve;
      src.start();
    });
  }
  return true;
}

/** Perekam mikrofon; butuh HTTPS dan izin pengguna. */
export async function mulaiRekam() {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const potongan = [];
  const mr = new MediaRecorder(stream);
  mr.ondataavailable = e => { if (e.data.size) potongan.push(e.data); };
  mr.start();
  return {
    stop: () => new Promise(resolve => {
      mr.onstop = () => {
        stream.getTracks().forEach(t => t.stop());
        resolve(new Blob(potongan, { type: mr.mimeType || 'audio/mp4' }));
      };
      mr.stop();
    }),
  };
}

function klip(path, kali) {
  return new Promise((resolve, reject) => {
    let sisa = kali;
    const el = new Audio(path);
    el.onerror = () => reject(new Error('klip tidak ada: ' + path));
    el.onended = () => {
      if (--sisa > 0) { el.currentTime = 0; el.play().catch(() => resolve(true)); }
      else resolve(true);
    };
    el.play().catch(reject);
  });
}

/**
 * Umumkan satu panggilan.
 * @param {string} ruang nama ruang, mis. 'Meeting Room Lantai 1'
 * @param {{ulang?:number, paksa?:boolean}} [opsi] paksa: abaikan jeda anti-spam
 * @returns {Promise<'klip'|'ucapan'|'dilewati'|'diam'>}
 */
export async function panggil(ruang, opsi = {}) {
  if (!diizinkan) return 'diam';

  const kunci = slug(ruang);
  const now = Date.now();
  if (!opsi.paksa && now - (terakhir.get(kunci) || 0) < JEDA_SAMA) return 'dilewati';
  terakhir.set(kunci, now);

  const kali = opsi.ulang ?? ULANG;

  // Urutan: rekaman sendiri -> klip di audio/ -> ucapan perangkat.
  try {
    const rekaman = await ambilRekaman(ruang);
    if (rekaman) { await putarBuffer(rekaman, kali); return 'rekaman'; }
  } catch (_) {}

  try {
    await klip(`${BASE}/panggilan-${kunci}${EXT}`, kali);
    return 'klip';
  } catch (_) {
    return ucap(`Panggilan dari ${ruang}`, kali) ? 'ucapan' : 'diam';
  }
}
