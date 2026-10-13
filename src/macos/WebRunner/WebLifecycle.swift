// SPDX-License-Identifier: GPL-2.0-or-later
enum WebLifecycle {
    // WKWebView has no Android pauseTimers API. Retain timeout and animation
    // callbacks while paused, and resume them without losing cancellation IDs.
    static let script = """
    (() => {
      const timeout = window.setTimeout.bind(window), interval = window.setInterval.bind(window);
      const clearTimeout = window.clearTimeout.bind(window), clearInterval = window.clearInterval.bind(window);
      const raf = window.requestAnimationFrame.bind(window), cancelRaf = window.cancelAnimationFrame.bind(window);
      const delayed = new Map(), frames = new Map(); let paused = false, nextFrame = 1, animations = [];
      function invoke(fn, args) { if (typeof fn === 'function') fn(...args); else (0, eval)(String(fn)); }
      window.setTimeout = (fn, ms, ...args) => {
        const id = timeout(() => { if (paused) delayed.set(id, () => invoke(fn, args)); else invoke(fn, args); }, ms);
        return id;
      };
      window.setInterval = (fn, ms, ...args) => interval(() => { if (!paused) invoke(fn, args); }, ms);
      window.clearTimeout = id => { delayed.delete(id); clearTimeout(id); };
      window.clearInterval = id => { delayed.delete(id); clearInterval(id); };
      function schedule(id, entry) {
        entry.handle = raf(time => {
          if (!frames.has(id)) return;
          if (!paused) { frames.delete(id); entry.fn(time); }
        });
      }
      window.requestAnimationFrame = fn => { const id = nextFrame++, entry = {fn, handle: 0}; frames.set(id, entry); if (!paused) schedule(id, entry); return id; };
      window.cancelAnimationFrame = id => { const entry = frames.get(id); if (entry) cancelRaf(entry.handle); frames.delete(id); };
      window.__huskPauseTimers = value => {
        if (paused === value) return;
        paused = value;
        if (paused) {
          frames.forEach(entry => cancelRaf(entry.handle));
          animations = document.getAnimations().filter(a => a.playState === 'running'); animations.forEach(a => a.pause());
        } else {
          const callbacks = Array(delayed.entries());
          callbacks.forEach(([id, fn]) => timeout(() => { if (!paused && delayed.delete(id)) fn(); }, 0));
          frames.forEach((entry, id) => schedule(id, entry));
          animations.forEach(a => a.play()); animations = [];
        }
      };
    })();
    """
}
