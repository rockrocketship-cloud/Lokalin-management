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

let diizinkan = false;
let suaraID = null;
const terakhir = new Map();   // slug ruang -> timestamp

function pilihSuaraID() {
  if (!('speechSynthesis' in window)) return;
  const v = speechSynthesis.getVoices();
  suaraID = v.find(x => x.lang === 'id-ID')
         || v.find(x => x.lang && x.lang.toLowerCase().startsWith('id'))
         || null;
}
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
    const u = new SpeechSynthesisUtterance(' ');
    u.volume = 0;
    speechSynthesis.speak(u);
    pilihSuaraID();
  } catch (_) {
    return false;
  }
  return true;
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
    for (let i = 0; i < kali; i++) {
      const u = new SpeechSynthesisUtterance(teks);
      u.lang = 'id-ID';
      if (suaraID) u.voice = suaraID;
      u.rate = 0.95;                     // sedikit lebih lambat, lebih jelas
      speechSynthesis.speak(u);          // antre, tidak saling memotong
    }
    return true;
  } catch (_) {
    return false;
  }
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
  try {
    await klip(`${BASE}/panggilan-${kunci}${EXT}`, kali);
    return 'klip';
  } catch (_) {
    return ucap(`Panggilan dari ${ruang}`, kali) ? 'ucapan' : 'diam';
  }
}
