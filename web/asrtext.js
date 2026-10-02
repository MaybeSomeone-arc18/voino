// Text clean-up for speech recognition output. Pure functions, no dependencies.
// collapseRepeats: tiny Whisper models sometimes loop ("raha hai raha hai raha hai ...").
// applyVocabulary: snap near-miss words to the user's own word list (names, product terms).
(function (root) {
  function collapseRepeats(text) {
    const words = text.split(/\s+/).filter(Boolean);
    const key = (w) => w.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
    let changed = true;
    let out = words;
    // phrases of 1 to 4 words repeated 3 or more times in a row are kept once... or twice for short ones
    while (changed) {
      changed = false;
      for (let n = 1; n <= 4 && !changed; n++) {
        for (let i = 0; i + n * 3 <= out.length && !changed; i++) {
          let reps = 1;
          while (i + (reps + 1) * n <= out.length) {
            let same = true;
            for (let k = 0; k < n; k++) if (key(out[i + k]) !== key(out[i + reps * n + k])) { same = false; break; }
            if (!same) break;
            reps++;
          }
          if (reps >= 3) { out = out.slice(0, i + n).concat(out.slice(i + reps * n)); changed = true; }
        }
      }
    }
    return out.join(' ');
  }

  function lev(a, b) {
    const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
    for (let j = 0; j <= b.length; j++) d[0][j] = j;
    for (let i = 1; i <= a.length; i++)
      for (let j = 1; j <= b.length; j++)
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    return d[a.length][b.length];
  }

  function matchCase(from, to) {
    if (from === from.toUpperCase() && from.length > 1) return to.toUpperCase();
    if (from[0] === from[0].toUpperCase() && from[0] !== from[0].toLowerCase()) return to[0].toUpperCase() + to.slice(1);
    return to;
  }

  // Replace a word by a vocabulary entry when they differ by at most 25% of the length (and at most 2 edits)
  // and share the first letter. Exact vocabulary words and very short words are never touched.
  function applyVocabulary(text, vocab) {
    const list = (vocab || []).map((w) => String(w).trim()).filter((w) => w.length >= 4);
    if (!list.length) return text;
    const lower = list.map((w) => w.toLowerCase());
    return text.replace(/[\p{L}\p{N}']+/gu, (w) => {
      const lw = w.toLowerCase();
      if (lw.length < 4 || lower.includes(lw)) return w;
      let best = null, bestD = 99;
      for (let i = 0; i < lower.length; i++) {
        const v = lower[i];
        if (v[0] !== lw[0] || Math.abs(v.length - lw.length) > 2) continue;
        const dist = lev(lw, v);
        if (dist <= 2 && dist <= Math.floor(Math.max(v.length, lw.length) * 0.25) && dist < bestD) { best = list[i]; bestD = dist; }
      }
      return best ? matchCase(w, best) : w;
    });
  }

  const api = { collapseRepeats, applyVocabulary };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.voinoAsrText = api;
})(typeof window !== 'undefined' ? window : globalThis);
