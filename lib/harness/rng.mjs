// /lib/rng.mjs: the seeded random source every item generator uses. The same seed
// always gives the same sequence (mulberry32), so a generator is deterministic and
// a validation can replay it. Math.random is not available to generators.

export function makeRng(seed) {
  let s = (Number(seed) >>> 0) || 1;

  function next() {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  // An integer from min to max, both included.
  function int(min, max) {
    const lo = Math.ceil(min);
    const hi = Math.floor(max);
    return lo + Math.floor(next() * (hi - lo + 1));
  }

  function pick(list) {
    return list[int(0, list.length - 1)];
  }

  // A shuffled copy (Fisher-Yates).
  function shuffle(list) {
    const copy = list.slice();
    for (let i = copy.length - 1; i > 0; i--) {
      const j = int(0, i);
      [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
  }

  // n distinct elements.
  function sample(list, n) {
    return shuffle(list).slice(0, n);
  }

  function bool(p = 0.5) {
    return next() < p;
  }

  // 1 or -1.
  function sign() {
    return bool() ? 1 : -1;
  }

  return Object.freeze({ next, int, pick, shuffle, sample, bool, sign });
}
