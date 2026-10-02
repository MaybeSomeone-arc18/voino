// Devanagari -> Roman (Hinglish-style) transliteration, so Hindi speech shows up in English letters.
// Pure functions, no dependencies. Whisper writes Hindi in Devanagari; Voino shows and processes Roman text.
const WORDS = {
  'है': 'hai', 'हैं': 'hain', 'में': 'mein', 'नहीं': 'nahi', 'और': 'aur', 'क्या': 'kya', 'का': 'ka', 'की': 'ki',
  'के': 'ke', 'को': 'ko', 'से': 'se', 'पर': 'par', 'यह': 'yeh', 'वह': 'woh', 'मैं': 'main', 'हम': 'hum',
  'आप': 'aap', 'तो': 'toh', 'भी': 'bhi', 'कि': 'ki', 'ये': 'ye', 'वो': 'wo', 'कल': 'kal', 'आज': 'aaj',
  'हो': 'ho', 'था': 'tha', 'थी': 'thi', 'थे': 'the', 'मुझे': 'mujhe', 'हमें': 'hume', 'तुम': 'tum', 'एक': 'ek',
  'करना': 'karna', 'करो': 'karo', 'कर': 'kar', 'होगा': 'hoga', 'होगी': 'hogi', 'चाहिए': 'chahiye',
};
const IND = { 'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऑ': 'o' };
const MAT = { 'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'ri', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ॉ': 'o', 'ॅ': 'e' };
const CON = {
  'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n', 'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'n',
  'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n', 'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
  'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
  'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l', 'क़': 'q', 'ख़': 'kh', 'ग़': 'g', 'ज़': 'z', 'ड़': 'r', 'ढ़': 'rh', 'फ़': 'f',
};
const NUKTA = { 'क': 'q', 'ख': 'kh', 'ग': 'g', 'ज': 'z', 'ड': 'r', 'ढ': 'rh', 'फ': 'f' };
const DIGITS = '०१२३४५६७८९';

function romanizeWord(w) {
  if (WORDS[w]) return WORDS[w];
  // Build syllables: {c: consonant string, v: vowel string or null (inherent a)}.
  const syl = [];
  let out = '';
  const chars = [...w];
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    if (IND[ch]) { syl.push({ c: '', v: IND[ch], fixed: true }); continue; }
    if (CON[ch]) {
      let c = CON[ch];
      if (chars[i + 1] === '\u093C' && NUKTA[ch]) { c = NUKTA[ch]; i++; }
      syl.push({ c, v: null });
      continue;
    }
    const last = syl[syl.length - 1];
    if (MAT[ch] && last) { last.v = MAT[ch]; continue; }
    if (ch === '\u094D' && last) { last.v = ''; last.cluster = true; continue; } // virama: no vowel
    if (ch === '\u0902' || ch === '\u0901') { if (last) last.nasal = true; continue; }
    if (ch === '\u0903') { syl.push({ c: 'h', v: '', fixed: true }); continue; }
    if (ch === '\u093C') continue;
    const d = DIGITS.indexOf(ch);
    if (d >= 0) { syl.push({ raw: String(d) }); continue; }
    syl.push({ raw: ch });
  }
  // Schwa deletion, right to left: drop the inherent 'a' of a medial consonant when the next syllable keeps its vowel.
  const n = syl.length;
  const dropped = new Array(n).fill(false);
  for (let i = n - 1; i >= 0; i--) {
    const s = syl[i];
    if (s.raw !== undefined || s.v !== null || s.fixed) continue;
    if (i === n - 1) { dropped[i] = true; continue; }
    if (i > 0 && !dropped[i + 1] && syl[i + 1].raw === undefined && syl[i - 1].raw === undefined && syl[i - 1].v !== '') dropped[i] = true;
  }
  for (let i = 0; i < n; i++) {
    const s = syl[i];
    if (s.raw !== undefined) { out += s.raw; continue; }
    out += s.c + (s.v === null ? (dropped[i] ? '' : 'a') : s.v);
    if (s.nasal) out += 'n';
  }
  return out;
}

function romanize(text) {
  return (text || '')
    .replace(/\u0964/g, '.')
    .replace(/[\u0900-\u097F]+/g, (w) => romanizeWord(w));
}

if (typeof window !== 'undefined') window.voinoRomanize = romanize;
if (typeof module !== 'undefined') module.exports = { romanize };
