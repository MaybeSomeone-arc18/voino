// Tiny tactile feedback for UI switches. Browsers expose no touchpad haptics API, so:
// - Android Chrome: real vibration through navigator.vibrate.
// - Desktop (and iOS/Safari, which have no vibrate): a very short, quiet click sound instead.
window.voinoFeedback = function () {
  try {
    if (navigator.vibrate) navigator.vibrate(18);
  } catch (_) {}
  try {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) return;
    const ctx = (window.__voinoTickCtx = window.__voinoTickCtx || new C());
    if (ctx.state === 'suspended') ctx.resume();
    const t = ctx.currentTime;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = 'sine';
    o.frequency.setValueAtTime(1800, t);
    o.frequency.exponentialRampToValueAtTime(600, t + 0.03);
    g.gain.setValueAtTime(0.05, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.045);
    o.connect(g);
    g.connect(ctx.destination);
    o.start(t);
    o.stop(t + 0.06);
  } catch (_) {}
};
