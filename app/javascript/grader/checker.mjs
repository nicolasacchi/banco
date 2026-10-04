// banco expression answer checker, promoted from the 2026-10-02 spike (docs/decisions.md D-029).
// Pure ESM, no Node or DOM APIs: runs in Node and in the browser.
// Compute Engine is injected and used ONLY as a LaTeX -> MathJSON parser in
// `form: 'raw'` mode. Value equivalence and form constraints are computed by this
// module on the raw MathJSON tree, so a Compute Engine upgrade can only change
// parsing, never grading semantics.
//
//   import { ComputeEngine } from '@cortex-js/compute-engine';
//   const checker = createChecker({ ComputeEngine });
//   const item = checker.compile({ expected: '2\\sqrt{2}', form: ['radical_simplified'],
//                                  errors: [{ code: 'extract_wrong', latex: '4\\sqrt{2}' }] });
//   item.problems            // [] when the instance is well generated
//   item.check('\\sqrt{8}')  // { verdict: 'wrong_form', form_violations: ['radicand_not_reduced'], ... }

export const CHECKER_VERSION = '1.0.0';

// ---------------------------------------------------------------- errors
class DomainError extends Error { constructor(m) { super(m); this.kind = 'domain'; } }
class Fallback extends Error { constructor(m) { super(m); this.kind = 'fallback'; } }
class InputError extends Error { constructor(code, detail) { super(code); this.code = code; this.detail = detail; } }

// ---------------------------------------------------------------- PRNG (deterministic)
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------------------------------------------------------------- exact rationals (BigInt)
const babs = (a) => (a < 0n ? -a : a);
function bgcd(a, b) { a = babs(a); b = babs(b); while (b) { const t = a % b; a = b; b = t; } return a; }
function Q(n, d = 1n) {
  if (d === 0n) throw new DomainError('division_by_zero');
  if (d < 0n) { n = -n; d = -d; }
  const g = bgcd(n, d) || 1n;
  return { n: n / g, d: d / g };
}
const qadd = (a, b) => Q(a.n * b.d + b.n * a.d, a.d * b.d);
const qmul = (a, b) => Q(a.n * b.n, a.d * b.d);
const qneg = (a) => ({ n: -a.n, d: a.d });
const qinv = (a) => Q(a.d, a.n);
const qzero = (a) => a.n === 0n;
const qeq = (a, b) => a.n === b.n && a.d === b.d;
function bitlen(x) { x = babs(x); return x === 0n ? 0 : x.toString(2).length; }
function qToFloat(q) {
  let { n, d } = q;
  const shift = Math.max(bitlen(n), bitlen(d)) - 900;
  if (shift > 0) { const s = BigInt(shift); n >>= s; d >>= s; if (d === 0n) return n === 0n ? 0 : Math.sign(Number(n)) * Infinity; }
  return Number(n) / Number(d);
}
const DEC_EXP_CAP = 400;
const NUM_RE = /^([+-]?)(\d*)(?:\.(\d*))?(?:e([+-]?\d+))?$/i;
function decToQ(str) {
  // "12", "-0.75", "1e-7", "3.0" -> exact rational
  const m = str.trim().match(NUM_RE);
  if (!m) throw new InputError('bad_number', str);
  const [, sign, ip, fp = '', ex] = m;
  let n = BigInt((ip || '0') + fp);
  let d = 10n ** BigInt(fp.length);
  if (ex) {
    // An exponent is bounded before the power is taken: 10n ** 99999999n holds the
    // single-threaded worker for tens of seconds.
    if (ex.replace(/^[+-]/, '').replace(/^0+/, '').length > 3 || Math.abs(Number(ex)) > DEC_EXP_CAP) throw new InputError('number_too_large', str);
    const e = BigInt(ex);
    if (e >= 0n) n *= 10n ** e; else d *= 10n ** -e;
  }
  if (sign === '-') n = -n;
  return Q(n, d);
}

// ---------------------------------------------------------------- integer helpers (Number, exact below 2^53)
const SQF_CAP = 1e12;
function factorSmall(nBig) {
  // returns Map prime -> exponent, for 1 <= n <= SQF_CAP; else throws Fallback
  if (nBig > BigInt(SQF_CAP)) throw new Fallback('radicand_too_large');
  let n = Number(nBig);
  const f = new Map();
  for (let p = 2; p * p <= n; p += (p === 2 ? 1 : 2)) {
    while (n % p === 0) { f.set(p, (f.get(p) || 0) + 1); n /= p; }
  }
  if (n > 1) f.set(n, (f.get(n) || 0) + 1);
  return f;
}
function powerDecomp(nBig, idx) {
  // n = s^idx * k with k idx-free. n >= 1.
  if (nBig === 0n) return [0n, 1n];
  const f = factorSmall(nBig);
  let s = 1n, k = 1n;
  for (const [p, e] of f) {
    s *= BigInt(p) ** BigInt(Math.floor(e / idx));
    k *= BigInt(p) ** BigInt(e % idx);
  }
  return [s, k];
}

// ---------------------------------------------------------------- exact surd field Q(sqrt k1, sqrt k2, ...)
// value = Map<squarefree bigint k, rational c> meaning sum c * sqrt(k); k = 1n is the rational part.
const sOfQ = (q) => { const m = new Map(); if (!qzero(q)) m.set(1n, q); return m; };
function sAdd(a, b) {
  const m = new Map(a);
  for (const [k, v] of b) {
    const s = m.has(k) ? qadd(m.get(k), v) : v;
    if (qzero(s)) m.delete(k); else m.set(k, s);
  }
  return m;
}
const sNeg = (a) => new Map([...a].map(([k, v]) => [k, qneg(v)]));
function sMul(a, b) {
  let m = new Map();
  for (const [k1, v1] of a) for (const [k2, v2] of b) {
    const g = bgcd(k1, k2);
    m = sAdd(m, new Map([[(k1 / g) * (k2 / g), qmul(qmul(v1, v2), Q(g))]]));
  }
  return m;
}
const sIsRational = (a) => a.size === 0 || (a.size === 1 && a.has(1n));
const sRational = (a) => (a.size === 0 ? Q(0n) : a.get(1n));
function sEq(a, b) {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) { const w = b.get(k); if (!w || !qeq(v, w)) return false; }
  return true;
}
function sToFloat(a) { let x = 0; for (const [k, v] of a) x += qToFloat(v) * Math.sqrt(Number(k)); return x; }
function sInv(a) {
  if (a.size === 0) throw new DomainError('division_by_zero');
  if (a.size === 1) { const [[k, c]] = [...a]; return new Map([[k, qinv(qmul(c, Q(k)))]]); }
  // multiply by the conjugate w.r.t. each prime dividing some radicand (multiquadratic norm)
  const primes = new Set();
  for (const k of a.keys()) if (k !== 1n) for (const p of factorSmall(k).keys()) primes.add(BigInt(p));
  let num = sOfQ(Q(1n)), den = a;
  for (const p of primes) {
    const conj = new Map([...den].map(([k, v]) => [k, k % p === 0n ? qneg(v) : v]));
    num = sMul(num, conj); den = sMul(den, conj);
  }
  if (!sIsRational(den)) throw new Fallback('inverse_not_rationalised');
  const r = sRational(den);
  if (qzero(r)) throw new DomainError('division_by_zero');
  return sMul(num, sOfQ(qinv(r)));
}
function sSign(a) { if (a.size === 0) return 0; const x = sToFloat(a); if (x === 0 || !Number.isFinite(x)) throw new Fallback('sign_undecidable'); return Math.sign(x); }
function sRoot(a, idx) {
  if (!sIsRational(a)) throw new Fallback('nested_radical');
  const q = sRational(a);
  if (qzero(q)) return new Map();
  const neg = q.n < 0n;
  if (neg && idx % 2 === 0) throw new DomainError('even_root_of_negative');
  const n = babs(q.n), d = q.d;
  // root(n/d) = root(n * d^(idx-1)) / d
  const [s, k] = powerDecomp(n * d ** BigInt(idx - 1), idx);
  if (idx === 2) return new Map([[k, Q(neg ? -s : s, d)]]);
  if (k !== 1n) throw new Fallback('irrational_higher_root');
  return sOfQ(Q(neg ? -s : s, d));
}
const POW_CAP = 1000n;
function sPow(base, e) {
  if (e.d === 1n) {
    let k = e.n;
    if (babs(k) > POW_CAP) throw new Fallback('exponent_too_large');
    if (k === 0n) { if (base.size === 0) throw new DomainError('zero_to_zero'); return sOfQ(Q(1n)); }
    let b = k < 0n ? sInv(base) : base;
    k = babs(k);
    let r = sOfQ(Q(1n));
    while (k > 0n) { if (k & 1n) r = sMul(r, b); k >>= 1n; if (k) b = sMul(b, b); }
    return r;
  }
  if (e.d === 2n || e.d === 3n) { return sPow(sRoot(base, Number(e.d)), Q(e.n)); }
  throw new Fallback('fractional_exponent');
}

// ---------------------------------------------------------------- input normalisation (string level)
const SUP = { '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-', '⁺': '+' };
function matchGroup(s, i) {
  // s[i] starts an opener; returns index after the matching closer, or -1
  if (s.startsWith('\\left(', i)) {
    let depth = 0;
    for (let j = i; j < s.length; j++) {
      if (s.startsWith('\\left', j)) depth++;
      else if (s.startsWith('\\right', j)) { depth--; if (depth === 0) { const end = s.indexOf(')', j); return end < 0 ? -1 : end + 1; } }
    }
    return -1;
  }
  const pairs = { '(': ')', '{': '}', '[': ']' };
  const open = s[i], close = pairs[open];
  if (!close) return -1;
  let depth = 0;
  for (let j = i; j < s.length; j++) {
    if (s[j] === open) depth++;
    else if (s[j] === close) { depth--; if (depth === 0) return j + 1; }
  }
  return -1;
}
const ROOT_OP_RE = /\\surd|(?<![a-zA-Z\\])(?:sqrt|rad)(?=\s*(?:\(|\{|\\left\(|\d))/;
const LEADING_DECIMAL_RE = /^\d+(?:\{,\}\d+|[.,]\d+)?/;
function rewriteRootOperators(s, flags) {
  // `\surd X` (what MathLive emits for a typed √) and plain-text `rad`/`sqrt` -> \sqrt{X}
  for (let guard = 0; guard < 50; guard++) {
    const m = s.match(ROOT_OP_RE);
    if (!m) return s;
    flags.add(m[0] === '\\surd' ? 'surd' : 'root_word');
    let i = m.index + m[0].length;
    while (s[i] === ' ') i++;
    let content, end;
    if (s.startsWith('\\left(', i)) { end = matchGroup(s, i); if (end < 0) throw new InputError('unbalanced'); content = s.slice(i + 6, s.lastIndexOf('\\right', end)); }
    else if (s[i] === '(' || s[i] === '{') { end = matchGroup(s, i); if (end < 0) throw new InputError('unbalanced'); content = s.slice(i + 1, end - 1); }
    else if (/\d/.test(s[i] || '')) { const d = s.slice(i).match(LEADING_DECIMAL_RE)[0]; content = d; end = i + d.length; }
    else if (/[a-zA-Z]/.test(s[i] || '')) { content = s[i]; end = i + 1; }
    else throw new InputError('empty_root');
    s = s.slice(0, m.index) + '\\sqrt{' + content + '}' + s.slice(end);
  }
  return s;
}
export function normalizeInput(input, source = 'mathlive') {
  const flags = new Set();
  if (typeof input !== 'string') throw new InputError('not_a_string');
  let s = input.normalize('NFC').trim();
  // an empty MathLive box means the answer is incomplete
  if (/\\placeholder\b/.test(s)) throw new InputError('incomplete_placeholder');
  // spacing and style commands carry no meaning (strip before ':' handling: `\:` is a space)
  s = s.replace(/\\(?:[,;:! ]|quad|qquad|displaystyle|textstyle)/g, ' ').replace(/~/g, ' ');
  // Italian nested grouping ( ) [ ] { }: square and curly brackets are parentheses here (not lists or sets);
  // keep the optional root index \sqrt[3]{..}
  s = s.replace(/\\sqrt\s*\[([^\]]*)\]/g, '\\sqrt\u0001$1\u0002');
  s = s.replace(/\\left\s*(?:\[|\\lbrack|\\\{|\\lbrace)/g, '\\left(').replace(/\\right\s*(?:\]|\\rbrack|\\\}|\\rbrace)/g, '\\right)');
  s = s.replace(/\\lbrack|\\lbrace|\\\{|\[/g, '(').replace(/\\rbrack|\\rbrace|\\\}|\]/g, ')');
  s = s.replace(/\u0001/g, '[').replace(/\u0002/g, ']');
  s = s.replace(/[−‒–—﹣－]/g, '-');
  s = s.replace(/[·⋅•∙]/g, '\\cdot ').replace(/×/g, '\\times ').replace(/÷/g, '\\div ');
  s = s.replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+/g, (m) => '^{' + [...m].map((c) => SUP[c]).join('') + '}');
  if (/\\?%\s*$/.test(s)) { flags.add('percent'); s = s.replace(/\\?%\s*$/, ''); }
  s = s.replace(/√/g, '\\surd ');
  // "2 1/2" or "2 5": TeX ignores the space and reads 21/2 or 25
  if (/\d\s+\d/.test(s.replace(/\\[a-zA-Z]+/g, ' x '))) throw new InputError('ambiguous_digit_space');
  if (source === 'text') {
    if (/\d\s*,\s+\d|\d\s+,\s*\d/.test(s)) throw new InputError('ambiguous_comma');
    s = s.replace(/\*/g, '\\cdot ');
    // ^(...) -> ^{...}
    for (let i = s.indexOf('^'); i >= 0; i = s.indexOf('^', i + 1)) {
      let j = i + 1; while (s[j] === ' ') j++;
      if (s[j] === '(') { const end = matchGroup(s, j); if (end < 0) throw new InputError('unbalanced'); s = s.slice(0, i + 1) + '{' + s.slice(j + 1, end - 1) + '}' + s.slice(end); }
    }
  }
  // MathLive (smartSuperscript, the default) leaves the superscript after one digit: typing 2^10 emits `2^10`,
  // rendered 2¹0 and read by TeX/CE as 2^1·0. Do not guess: ask the student to fix the exponent.
  if (source === 'mathlive' && /\^\s*\d\d/.test(s)) throw new InputError('ambiguous_exponent');
  // Italian thousands separator: "1.000" is 1000 here and 1.0 to a parser that reads the dot as a decimal point.
  // Do not guess: a group of three digits after a dot (not after a leading 0) is refused.
  if (/(?<![\d.])[1-9]\d{0,2}(?:\.\d{3})+(?!\d)/.test(s.replace(/\\[a-zA-Z]+/g, ' x '))) throw new InputError('thousands_separator');
  // plain text: x^12 -> x^{12}, x^-1 -> x^{-1} (student intent, not TeX rules)
  s = s.replace(/\^\s*(-?\d+)/g, '^{$1}');
  // decimal comma between digits: 2,5 -> 2{,}5 (MathLive emits {,} itself when decimalSeparator=',')
  s = s.replace(/(\d),(?=\d)/g, '$1{,}');
  // periodic notation written with parentheses is ambiguous with multiplication: 0,5(2)
  if (/\d(?:\{,\}|[.,])\d*\s*(?:\\left)?\(\s*\d+\s*(?:\\right)?\)/.test(s)) throw new InputError('ambiguous_periodic');
  s = rewriteRootOperators(s, flags);
  // Italian ':' is division with the precedence of '/'; CE 0.146 parses ':' as a lowest-precedence,
  // right-associative Colon (6:3+1 -> 6:(3+1), 12:4:3 -> 12:(4:3)). Rewrite to \div, which CE parses correctly.
  if (/:/.test(s)) { flags.add('division_operator'); s = s.replace(/:/g, '\\div '); }
  if (/\\div/.test(s)) flags.add('division_operator');
  return { latex: s, flags };
}

// ---------------------------------------------------------------- MathJSON (raw) -> internal AST
// node kinds: num{q, kind:int|dec|periodic}, sym{name}, pi, add{args}, neg{arg}, mul{args, implicit},
//             div{num, den, colon}, pow{base, exp}, root{arg, idx}, abs{arg}, paren{arg}, eq{lhs, rhs}
const CONSTANTS = new Set(['Pi']);
function fromJson(j) {
  if (typeof j === 'number') {
    if (!Number.isFinite(j)) throw new InputError('not_finite');
    const q = decToQ(String(j));
    return { t: 'num', q, kind: Number.isInteger(j) ? 'int' : 'dec' };
  }
  if (typeof j === 'string') {
    if (j === 'Nothing') throw new InputError('empty');
    if (CONSTANTS.has(j)) return { t: 'pi' };
    if (/^[A-Za-z](?:_\d+|_\{?\d+\}?)?$/.test(j)) return { t: 'sym', name: j };
    throw new InputError('unknown_symbol', j);
  }
  if (j && typeof j === 'object' && !Array.isArray(j)) {
    if (typeof j.num === 'string') {
      if (/[()]/.test(j.num)) throw new InputError('unsupported_number', j.num);
      const q = decToQ(j.num);
      return { t: 'num', q, kind: q.d === 1n && !j.num.includes('.') ? 'int' : 'dec' };
    }
    if (typeof j.sym === 'string') return fromJson(j.sym);
    if (j.fn) return fromJson(j.fn);
    throw new InputError('unsupported_json');
  }
  if (!Array.isArray(j) || typeof j[0] !== 'string') throw new InputError('unsupported_json');
  const [op, ...a] = j;
  const A = () => a.map(fromJson);
  switch (op) {
    case 'Add': return { t: 'add', args: A() };
    case 'Subtract': { const [x, y] = A(); return { t: 'add', args: [x, { t: 'neg', arg: y }] }; }
    case 'Negate': return { t: 'neg', arg: fromJson(a[0]) };
    case 'Multiply': return { t: 'mul', args: A(), implicit: false };
    case 'InvisibleOperator': {
      const args = A();
      // mixed number 2\frac{1}{2}: ambiguous (2 + 1/2 or 2 * 1/2)
      for (let i = 0; i + 1 < args.length; i++) {
        if (args[i].t === 'num' && args[i].kind === 'int' && isIntFrac(args[i + 1])) throw new InputError('ambiguous_mixed_number');
      }
      return { t: 'mul', args, implicit: true };
    }
    case 'Divide': { const [x, y] = A(); return { t: 'div', num: x, den: y, colon: false }; }
    case 'Colon': { const [x, y] = A(); return { t: 'div', num: x, den: y, colon: true }; }
    case 'Rational': {
      const [x, y] = a;
      if (Number.isInteger(x) && Number.isInteger(y)) return { t: 'num', q: Q(BigInt(x), BigInt(y)), kind: 'periodic' };
      throw new InputError('unsupported_rational');
    }
    case 'Power': { const [x, y] = A(); return { t: 'pow', base: x, exp: y }; }
    case 'Square': return { t: 'pow', base: fromJson(a[0]), exp: { t: 'num', q: Q(2n), kind: 'int' } };
    case 'Sqrt': return { t: 'root', arg: fromJson(a[0]), idx: 2 };
    case 'Root': {
      const idx = a[1];
      if (!Number.isInteger(idx) || idx < 2 || idx > 10) throw new InputError('unsupported_root_index');
      return { t: 'root', arg: fromJson(a[0]), idx };
    }
    case 'Abs': return { t: 'abs', arg: fromJson(a[0]) };
    case 'Delimiter': {
      if (a.length === 1 || (a.length === 2 && a[1] === "'()'")) {
        if (Array.isArray(a[0]) && a[0][0] === 'Sequence') throw new InputError('list_not_expected');
        return { t: 'paren', arg: fromJson(a[0]) };
      }
      throw new InputError('list_not_expected');
    }
    case 'Equal': { const [x, y] = A(); return { t: 'eq', lhs: x, rhs: y }; }
    case 'Less': case 'LessEqual': case 'Greater': case 'GreaterEqual': {
      if (a.length !== 2) throw new InputError('unsupported_operator', 'chained_relation');
      const [x, y] = A();
      return { t: 'rel', op: REL_OPS[op], lhs: x, rhs: y };
    }
    case 'Error': throw new InputError('syntax', JSON.stringify(a).slice(0, 80));
    default: throw new InputError('unsupported_operator', op);
  }
}
const REL_OPS = { Less: '<', LessEqual: '<=', Greater: '>', GreaterEqual: '>=' };
function isIntLit(n) { return n.t === 'num' && n.kind === 'int'; }
function isIntFrac(n) { return n.t === 'div' && !n.colon && isIntLit(n.num) && isIntLit(n.den); }

// ---------------------------------------------------------------- evaluation
function children(n) {
  switch (n.t) {
    case 'add': case 'mul': return n.args;
    case 'div': return [n.num, n.den];
    case 'pow': return [n.base, n.exp];
    case 'eq': case 'rel': return [n.lhs, n.rhs];
    case 'num': case 'sym': case 'pi': return [];
    default: return [n.arg];
  }
}
function freeVars(n, out = new Set()) {
  if (n.t === 'sym') out.add(n.name);
  for (const c of children(n)) freeVars(c, out);
  return out;
}
function hasRootOverVars(n) {
  if (n.t === 'root' && freeVars(n.arg).size) return true;
  if (n.t === 'pow' && freeVars(n.base).size) {
    const e = strip(n.exp);
    const intExp = (e.t === 'num' && e.q.d === 1n) || (e.t === 'neg' && strip(e.arg).t === 'num' && strip(e.arg).q.d === 1n);
    if (!intExp) return true;
  }
  return children(n).some(hasRootOverVars);
}
function evalExact(n, env) {
  switch (n.t) {
    case 'num': return sOfQ(n.q);
    case 'sym': { const v = env.get(n.name); if (!v) throw new Fallback('unbound'); return sOfQ(v); }
    case 'pi': throw new Fallback('pi');
    case 'paren': return evalExact(n.arg, env);
    case 'add': return n.args.reduce((acc, x) => sAdd(acc, evalExact(x, env)), new Map());
    case 'neg': return sNeg(evalExact(n.arg, env));
    case 'mul': return n.args.reduce((acc, x) => sMul(acc, evalExact(x, env)), sOfQ(Q(1n)));
    case 'div': return sMul(evalExact(n.num, env), sInv(evalExact(n.den, env)));
    case 'pow': {
      const e = evalExact(n.exp, env);
      if (!sIsRational(e)) throw new Fallback('irrational_exponent');
      return sPow(evalExact(n.base, env), sRational(e));
    }
    case 'root': return sRoot(evalExact(n.arg, env), n.idx);
    case 'abs': { const v = evalExact(n.arg, env); return sSign(v) < 0 ? sNeg(v) : v; }
    default: throw new Fallback('eval_' + n.t);
  }
}
function evalFloat(n, env) {
  switch (n.t) {
    case 'num': return qToFloat(n.q);
    case 'sym': return env.get(n.name);
    case 'pi': return Math.PI;
    case 'paren': return evalFloat(n.arg, env);
    case 'add': return n.args.reduce((acc, x) => acc + evalFloat(x, env), 0);
    case 'neg': return -evalFloat(n.arg, env);
    case 'mul': return n.args.reduce((acc, x) => acc * evalFloat(x, env), 1);
    case 'div': { const d = evalFloat(n.den, env); return d === 0 ? NaN : evalFloat(n.num, env) / d; }
    case 'pow': {
      const b = evalFloat(n.base, env), e = evalFloat(n.exp, env);
      if (b === 0 && e <= 0) return NaN;
      if (b < 0 && !Number.isInteger(e)) return NaN;
      return Math.pow(b, e);
    }
    case 'root': { const v = evalFloat(n.arg, env); if (v < 0) return n.idx % 2 ? -Math.pow(-v, 1 / n.idx) : NaN; return n.idx === 2 ? Math.sqrt(v) : Math.pow(v, 1 / n.idx); }
    case 'abs': return Math.abs(evalFloat(n.arg, env));
    default: return NaN;
  }
}
const REL_TOL = 1e-9, ABS_TOL = 1e-12;
const floatClose = (x, y) => Math.abs(x - y) <= Math.max(ABS_TOL, REL_TOL * Math.max(Math.abs(x), Math.abs(y)));

function cmpAt(A, B, qenv, fenv) {
  // {eq, exact} or null when the point is outside the domain of A or B
  try { const a = evalExact(A, qenv), b = evalExact(B, qenv); return { eq: sEq(a, b), exact: true }; }
  catch (e) { if (e instanceof DomainError) return null; if (!(e instanceof Fallback)) throw e; }
  const x = evalFloat(A, fenv), y = evalFloat(B, fenv);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return { eq: floatClose(x, y), exact: false };
}

export function valueEquivalent(A, B, opts = {}) {
  const { domain = {}, seed = 0x5eed, mode = 'exact', points = 8, maxAttempts = 60 } = opts;
  const vars = [...new Set([...freeVars(A), ...freeVars(B)])].sort();
  if (vars.length === 0) {
    if (mode === 'float') {
      const x = evalFloat(A, new Map()), y = evalFloat(B, new Map());
      if (!Number.isFinite(x) || !Number.isFinite(y)) return { equal: null, reason: 'undefined_value', method: 'float' };
      return { equal: floatClose(x, y), method: 'float' };
    }
    const r = cmpAt(A, B, new Map(), new Map());
    if (r === null) return { equal: null, reason: 'undefined_value', method: 'exact' };
    return { equal: r.eq, method: r.exact ? 'exact' : 'float' };
  }
  const rootVars = hasRootOverVars(A) || hasRootOverVars(B);
  const rng = mulberry32(seed);
  let valid = 0, allExact = true;
  for (let att = 0; att < maxAttempts && valid < points; att++) {
    const qenv = new Map(), fenv = new Map();
    for (const v of vars) {
      const dom = domain[v] || (rootVars ? 'positive' : 'real');
      if (mode === 'float') {
        // the design's proposal: real points in a moderate range, tolerance compare
        const mag = 0.25 + rng() * 4.75;
        fenv.set(v, dom === 'positive' || rng() < 0.5 ? mag : -mag);
      } else {
        const R = rootVars ? 60 : 10007;
        let k = 1 + Math.floor(rng() * R);
        if (dom !== 'positive' && rng() < 0.5) k = -k;
        qenv.set(v, Q(BigInt(k))); fenv.set(v, k);
      }
    }
    let r;
    if (mode === 'float') {
      const x = evalFloat(A, fenv), y = evalFloat(B, fenv);
      r = Number.isFinite(x) && Number.isFinite(y) ? { eq: floatClose(x, y), exact: false } : null;
    } else r = cmpAt(A, B, qenv, fenv);
    if (r === null) continue;
    if (!r.exact) allExact = false;
    const method = mode === 'float' ? 'float-sampled' : allExact ? 'exact-sampled' : 'mixed-sampled';
    if (!r.eq) return { equal: false, method, witness: Object.fromEntries(fenv) };
    valid++;
  }
  if (valid < Math.min(points, 4)) return { equal: null, reason: 'too_few_valid_points', method: 'sampled' };
  return { equal: true, method: mode === 'float' ? 'float-sampled' : allExact ? 'exact-sampled' : 'mixed-sampled', points: valid };
}

// ---------------------------------------------------------------- form analysis on the raw tree
function strip(n) { return n.t === 'paren' ? strip(n.arg) : n; }
function negExp(x) { x = strip(x); return x.t === 'neg' || (x.t === 'num' && x.q.n < 0n); }
function walk(n, f, ctx = { inDen: false }) {
  f(n, ctx);
  if (n.t === 'div') { walk(n.num, f, ctx); walk(n.den, f, { ...ctx, inDen: true }); return; }
  if (n.t === 'pow') { walk(n.base, f, negExp(n.exp) ? { ...ctx, inDen: true } : ctx); walk(n.exp, f, ctx); return; }
  for (const c of children(n)) walk(c, f, ctx);
}
function terms(n, sign = 1, out = []) {
  if (n.t === 'add') { n.args.forEach((x) => terms(x, sign, out)); return out; }
  if (n.t === 'neg' && n.arg.t !== 'paren') return terms(n.arg, -sign, out);
  if (n.t === 'paren' && strip(n).t === 'add' && sign === 1) return terms(strip(n), sign, out);
  out.push({ sign, node: n });
  return out;
}
// numeric literal: int | decimal | periodic | fraction of integer literals, with optional sign/parentheses
function numberForm(n) {
  n = strip(n);
  let sign = 1;
  if (n.t === 'neg') { sign = -1; n = strip(n.arg); }
  if (n.t === 'neg') return null; // -(-3) is a computation, not a number
  if (n.t === 'num') return { kind: n.kind, q: sign < 0 ? qneg(n.q) : n.q };
  if (n.t === 'div' && !n.colon) {
    let a = strip(n.num), b = strip(n.den), s = sign, signInDen = false;
    if (a.t === 'neg') { s = -s; a = strip(a.arg); }
    if (b.t === 'neg') { s = -s; b = strip(b.arg); signInDen = true; }
    if (isIntLit(a) && isIntLit(b) && b.q.n !== 0n) return { kind: 'frac', num: a.q.n, den: b.q.n, signInDen, q: Q((s < 0 ? -1n : 1n) * a.q.n, b.q.n) };
  }
  return null;
}
// monomial: [numeric coefficient] * prod(var^k), each var once, optionally divided by an integer literal
function flatFactors(n, acc = { sign: 1, factors: [] }) {
  n = strip(n);
  if (n.t === 'neg' && !numberForm(n)) { acc.sign = -acc.sign; return flatFactors(n.arg, acc); }
  if (n.t === 'mul') { n.args.forEach((x) => flatFactors(x, acc)); return acc; }
  acc.factors.push(n);
  return acc;
}
function monomialInfo(n) {
  n = strip(n);
  let coeff = Q(1n), sign = 1, coeffLits = 0, extraDen = null;
  if (n.t === 'neg') { sign = -1; n = strip(n.arg); }
  if (n.t === 'div' && !n.colon && isIntLit(strip(n.den)) && freeVars(n.num).size) { extraDen = strip(n.den).q.n; n = strip(n.num); }
  const ff = flatFactors(n);
  sign *= ff.sign;
  const factors = ff.factors;
  const vars = new Map();
  for (const f of factors) {
    const nf = numberForm(f);
    if (nf) { coeff = qmul(coeff, nf.q); coeffLits++; continue; }
    if (f.t === 'sym') { if (vars.has(f.name)) return null; vars.set(f.name, 1); continue; }
    if (f.t === 'pow' && strip(f.base).t === 'sym' && isIntLit(strip(f.exp)) && strip(f.exp).q.n >= 1n) {
      const name = strip(f.base).name; if (vars.has(name)) return null; vars.set(name, Number(strip(f.exp).q.n)); continue;
    }
    return null;
  }
  if (coeffLits > 1) return null; // 2·3x is not reduced
  if (extraDen !== null) { if (extraDen === 0n) return null; coeff = qmul(coeff, Q(1n, extraDen)); }
  if (sign < 0) coeff = qneg(coeff);
  const sig = [...vars].sort(([a], [b]) => (a < b ? -1 : 1)).map(([v, k]) => `${v}^${k}`).join('*');
  return { coeff, sig, extraDen, nvars: vars.size };
}
function radicalTermSig(n) {
  const roots = [];
  (function w(x) { x = strip(x); if (x.t === 'root') { roots.push(`${x.idx}:${JSON.stringify(x.arg, (k, v) => (typeof v === 'bigint' ? String(v) : v))}`); return; } for (const c of children(x)) w(c); })(n);
  if (!roots.length) return null;
  return roots.sort().join('|') + '#' + [...freeVars(n)].sort().join(',');
}
function numericLiteralCount(n) {
  if (numberForm(n)) return 1;
  return flatFactors(n).factors.filter((x) => numberForm(x)).length;
}
function factorList(n, out = []) {
  n = strip(n);
  if (n.t === 'neg') return factorList(n.arg, out);
  if (n.t === 'mul') { n.args.forEach((x) => factorList(x, out)); return out; }
  const e = n.t === 'pow' ? strip(n.exp) : null;
  if (e && isIntLit(e) && e.q.n >= 1n && e.q.n <= 12n && freeVars(n.base).size) {
    for (let i = 0n; i < e.q.n; i++) factorList(n.base, out);
    return out;
  }
  out.push(n);
  return out;
}
function termIntCoeff(n) {
  // integer coefficient of a term (product of its integer literal factors); null if a non-integer literal appears
  n = strip(n);
  if (n.t === 'neg') return termIntCoeff(n.arg);
  const fs = n.t === 'mul' ? n.args.map(strip) : [n];
  let c = 1n;
  for (const f of fs) { const nf = numberForm(f); if (!nf) continue; if (nf.kind !== 'int') return null; c *= babs(nf.q.n); }
  return c;
}
function isPrimitiveIntegerPoly(f) {
  let g = 0n;
  for (const t of terms(strip(f))) {
    const mi = monomialInfo(t.node);
    if (!mi || mi.coeff.d !== 1n) return true; // cannot tell: do not blame the common factor
    g = bgcd(g, mi.coeff.n);
  }
  return g === 1n || g === 0n;
}

// ---- polynomial helpers for the `reduced` form (exact, over Q; coefficients low to high)
function polyTrim(p) { while (p.length && qzero(p[p.length - 1])) p.pop(); return p; }
function polyInterp(xs, ys) {
  const out = [];
  for (let i = 0; i < xs.length; i++) {
    let term = [ys[i]];
    for (let j = 0; j < xs.length; j++) {
      if (j === i) continue;
      const inv = qinv(Q(xs[i] - xs[j]));
      const next = new Array(term.length + 1).fill(null).map(() => Q(0n));
      term.forEach((c, k) => { next[k + 1] = qadd(next[k + 1], qmul(c, inv)); next[k] = qadd(next[k], qmul(c, qmul(inv, Q(-xs[j])))); });
      term = next;
    }
    term.forEach((c, k) => { out[k] = qadd(out[k] || Q(0n), c); });
  }
  return polyTrim(out);
}
function polyRem(a, b) {
  a = a.slice();
  while (a.length >= b.length && a.length) {
    const f = qmul(a[a.length - 1], qinv(b[b.length - 1])), sh = a.length - b.length;
    for (let i = 0; i < b.length; i++) a[sh + i] = qadd(a[sh + i], qneg(qmul(f, b[i])));
    polyTrim(a);
  }
  return a;
}
function polyGcdDegree(a, b) {
  a = polyTrim(a.slice()); b = polyTrim(b.slice());
  if (!a.length || !b.length) return Math.max(a.length, b.length) - 1;
  while (b.length) { const r = polyRem(a, b); a = b; b = r; }
  return a.length - 1;
}
// the polynomial a node stands for in its single letter, or null (not a polynomial of degree <= 9)
function asPoly(n, name) {
  const xs = [], ys = [];
  try {
    for (let k = -5n; k <= 6n; k++) {
      const v = evalExact(n, new Map([[name, Q(k)]]));
      if (!sIsRational(v)) return null;
      xs.push(k); ys.push(sRational(v));
    }
  } catch { return null; }
  const p = polyInterp(xs, ys);
  return p.length - 1 <= 9 ? p : null;
}

const opDiv = (ans, ctx) => ctx.flags.has('division_operator') && numberForm(ans) && numberForm(ans).kind === 'frac';
const FORMS = {
  number(ans, ctx) { return numberForm(ans) && !opDiv(ans, ctx) ? [] : ['not_a_number']; },
  integer(ans) { const nf = numberForm(ans); return nf && nf.kind === 'int' ? [] : ['not_an_integer']; },
  fraction(ans, ctx) { const nf = numberForm(ans); return nf && (nf.kind === 'int' || nf.kind === 'frac') && !opDiv(ans, ctx) ? [] : ['not_a_fraction']; },
  decimal(ans) { const nf = numberForm(ans); return nf && (nf.kind === 'int' || nf.kind === 'dec') ? [] : ['not_a_decimal']; },
  percent(ans, ctx) { return ctx.flags.has('percent') ? [] : ['not_a_percentage']; },
  lowest_terms(ans) {
    const v = new Set();
    walk(ans, (x) => {
      const nf = x.t === 'div' ? numberForm(x) : null;
      if (nf && nf.kind === 'frac') {
        if (bgcd(nf.num, nf.den) !== 1n) v.add('not_lowest_terms');
        if (nf.den === 1n) v.add('denominator_one');
        if (nf.signInDen) v.add('sign_in_denominator');
      }
      if (x.t === 'div' && !x.colon && isIntLit(strip(x.den)) && !numberForm(x)) {
        // (6√3)/3, (2+2√3)/2, (6x)/8: the integer content of the numerator shares a factor with the denominator
        let g = strip(x.den).q.n;
        for (const t of terms(x.num)) { const c = termIntCoeff(t.node); if (c === null) { g = 1n; break; } g = bgcd(g, c); }
        if (g !== 1n) v.add('not_lowest_terms');
      }
    });
    return [...v];
  },
  // an algebraic fraction whose numerator and denominator (polynomials in one letter) still share a factor
  reduced(ans) {
    const v = new Set();
    walk(ans, (x) => {
      if (x.t !== 'div' || x.colon) return;
      const nv = freeVars(x.num), dv = freeVars(x.den);
      if (!nv.size || !dv.size) return;
      const all = new Set([...nv, ...dv]);
      if (all.size !== 1) return;
      const name = [...all][0];
      const a = asPoly(x.num, name), b = asPoly(x.den, name);
      if (a && b && polyGcdDegree(a, b) > 0) v.add('common_factor_not_cancelled');
    });
    return [...v];
  },
  single_power(ans) {
    const n = strip(ans);
    if (n.t !== 'pow') return ['not_a_single_power'];
    const b = strip(n.base), e = numberForm(n.exp);
    const baseOk = b.t === 'sym' || numberForm(b);
    return baseOk && e && e.kind === 'int' ? [] : ['not_a_single_power'];
  },
  monomial(ans) {
    const ts = terms(ans);
    if (ts.length !== 1) return ['not_a_monomial'];
    return monomialInfo(ts[0].node) ? [] : ['monomial_not_reduced'];
  },
  expanded(ans) {
    const sigs = new Set(), v = new Set();
    for (const t of terms(ans)) {
      const mi = monomialInfo(t.node);
      if (!mi) { v.add(numericLiteralCount(t.node) > 1 ? 'coefficients_not_multiplied' : 'not_expanded'); continue; }
      if (qzero(mi.coeff)) v.add('zero_term');
      if (sigs.has(mi.sig)) v.add('like_terms_not_combined');
      sigs.add(mi.sig);
    }
    return [...v];
  },
  rationalized(ans) {
    const v = new Set();
    walk(ans, (x, ctx) => { if (ctx.inDen && x.t === 'root') v.add('not_rationalized'); });
    return [...v];
  },
  radical_simplified(ans) {
    const v = new Set(FORMS.rationalized(ans));
    walk(ans, (x) => {
      if (x.t !== 'root') return;
      const r = strip(x.arg);
      if (r.t === 'root') v.add('nested_root');
      if (r.t === 'div') v.add('fraction_under_root');
      if (isIntLit(r)) {
        if (r.q.n <= 1n) v.add('trivial_root');
        else { try { const [s] = powerDecomp(r.q.n, x.idx); if (s !== 1n) v.add('radicand_not_reduced'); } catch { /* huge radicand: skip */ } }
      }
      walk(r, (y) => {
        if (y.t === 'pow' && strip(y.base).t === 'sym' && isIntLit(strip(y.exp)) && strip(y.exp).q.n >= BigInt(x.idx)) v.add('factor_not_extracted');
      });
      if (r.t === 'mul' && r.args.filter((y) => numberForm(y)).length > 1) v.add('radicand_not_multiplied');
    });
    let body = strip(ans);
    if (body.t === 'div' && isIntLit(strip(body.den))) body = body.num; // (a+b√c)/d is acceptable
    const sigs = new Set();
    let rationalTerms = 0;
    for (const t of terms(body)) {
      const node = strip(t.node);
      let nroots = 0;
      walk(node, (y) => { if (y.t === 'root') nroots++; });
      if (flatFactors(node).factors.filter((y) => y.t === 'root').length > 1) v.add('roots_not_multiplied');
      if (numericLiteralCount(node) > 1) v.add('coefficients_not_multiplied');
      const sig = radicalTermSig(node);
      if (sig === null) { if (!freeVars(node).size) rationalTerms++; continue; }
      if (sigs.has(sig)) v.add('like_radicals_not_combined');
      sigs.add(sig);
    }
    if (rationalTerms > 1) v.add('like_terms_not_combined');
    return [...v];
  },
  factored(ans, ctx) {
    const af = factorList(ans).filter((f) => freeVars(f).size);
    const ef = factorList(ctx.expected).filter((f) => freeVars(f).size);
    if ((af.length <= 1 && ef.length > 1) || (strip(ans).t === 'add' && strip(ctx.expected).t !== 'add')) return ['not_factored'];
    const used = new Array(ef.length).fill(false);
    const v = new Set();
    for (const f of af) {
      let hit = -1;
      for (let i = 0; i < ef.length && hit < 0; i++) {
        if (used[i]) continue;
        if (valueEquivalent(f, ef[i], ctx.opts).equal === true || valueEquivalent(f, { t: 'neg', arg: ef[i] }, ctx.opts).equal === true) hit = i;
      }
      if (hit < 0) v.add(isPrimitiveIntegerPoly(f) ? 'not_fully_factored' : 'common_factor_not_extracted');
      else used[hit] = true;
    }
    if (af.length < ef.length) v.add('not_fully_factored');
    return [...v];
  },
  // `r = expression` or `expression` for the unknown `r`: the letter is isolated; the other side
  // may be any expression (compare solution, whose other side must be a number).
  isolate(ans, ctx) {
    const n = strip(ans);
    if (n.t === 'eq') {
      const l = strip(n.lhs), r = strip(n.rhs);
      const symSide = l.t === 'sym' ? l : r.t === 'sym' ? r : null;
      if (!symSide || (ctx.unknown && symSide.name !== ctx.unknown)) return ['not_a_solution_statement'];
    }
    return [];
  },
  solution(ans, ctx) {
    const n = strip(ans);
    if (n.t === 'eq' || n.t === 'rel') {
      const l = strip(n.lhs), r = strip(n.rhs);
      const symSide = l.t === 'sym' ? l : r.t === 'sym' ? r : null;
      const numSide = l.t === 'sym' ? r : l;
      if (!symSide || (ctx.unknown && symSide.name !== ctx.unknown)) return ['not_a_solution_statement'];
      return numberForm(numSide) && !opDiv(numSide, ctx) ? [] : ['solution_not_computed'];
    }
    return numberForm(n) && !opDiv(n, ctx) ? [] : ['solution_not_computed'];
  },
};

// `x = value` -> value, for solution items. A relation (x < a, a >= x) becomes a canonical
// { t: 'rel', op, arg } with the unknown on the left (a > x is x < a); a relation without the
// unknown alone on one side gets op '?' and never equals anything.
function solutionValue(n, unknown) {
  const s = strip(n);
  if (s.t === 'rel') {
    const l = strip(s.lhs), r = strip(s.rhs);
    if (l.t === 'sym' && (!unknown || l.name === unknown)) return { t: 'rel', op: s.op, arg: s.rhs };
    if (r.t === 'sym' && (!unknown || r.name === unknown)) return { t: 'rel', op: FLIP[s.op], arg: s.lhs };
    return { t: 'rel', op: '?', arg: s };
  }
  if (s.t !== 'eq') return n;
  const l = strip(s.lhs), r = strip(s.rhs);
  if (l.t === 'sym' && (!unknown || l.name === unknown)) return s.rhs;
  if (r.t === 'sym' && (!unknown || r.name === unknown)) return s.lhs;
  return n;
}
const FLIP = { '<': '>', '<=': '>=', '>': '<', '>=': '<=' };
// Value equality of two solution values; a relation equals only a relation with the same
// direction and an equal bound.
function solEq(a, b, opts) {
  const ra = a.t === 'rel', rb = b.t === 'rel';
  if (!ra && !rb) return valueEquivalent(a, b, opts);
  if (ra !== rb || a.op === '?' || a.op !== b.op) return { equal: false, method: 'exact' };
  return valueEquivalent(a.arg, b.arg, opts);
}
function hasRel(n) { let f = false; walk(n, (y) => { if (y.t === 'rel') f = true; }); return f; }

// ---------------------------------------------------------------- public factory
export function createChecker({ ComputeEngine }) {
  const ce = new ComputeEngine();
  ce.latexOptions = { ...ce.latexOptions, decimalSeparator: '{,}' };

  function parse(input, source = 'mathlive') {
    try {
      const { latex, flags } = normalizeInput(input, source);
      if (!latex) throw new InputError('empty');
      const json = ce.parse(latex, { form: 'raw' }).json;
      let ast = fromJson(json);
      if (flags.has('percent')) ast = { t: 'div', num: ast, den: { t: 'num', q: Q(100n), kind: 'int' }, colon: false, percent: true };
      return { ok: true, ast, json, latex, flags };
    } catch (e) {
      if (e instanceof InputError) return { ok: false, code: e.code, detail: e.detail };
      return { ok: false, code: 'parser_exception', detail: String(e && e.message).slice(0, 120) };
    }
  }

  function compile(spec) {
    const { expected, form = [], errors = [], domain = {}, unknown = null, seed = 0x5eed, mode = 'exact', source = 'mathlive' } = spec;
    const opts = { domain, seed, mode };
    const problems = [];
    const exp = parse(expected, source);
    if (exp.ok && !form.includes('solution') && hasRel(exp.ast)) return { problems: ['expected_unparseable:unsupported_operator'], check: () => ({ verdict: 'invalid', code: 'item_broken' }) };
    if (!exp.ok) return { problems: [`expected_unparseable:${exp.code}`], check: () => ({ verdict: 'invalid', code: 'item_broken' }) };
    const isSol = form.includes('solution');
    const strips = isSol || form.includes('isolate');
    const expVal = strips ? solutionValue(exp.ast, unknown) : exp.ast;
    const errs = [];
    for (const e of errors) {
      const p = parse(e.latex, source);
      if (!p.ok) { problems.push(`error_unparseable:${e.code}`); continue; }
      errs.push({ code: e.code, ast: strips ? solutionValue(p.ast, unknown) : p.ast });
    }
    // generator constraints: the correct answer never matches an error; errors never collide
    for (const e of errs) if (solEq(expVal, e.ast, opts).equal !== false) problems.push(`error_equals_expected:${e.code}`);
    for (let i = 0; i < errs.length; i++) for (let j = i + 1; j < errs.length; j++) {
      if (solEq(errs[i].ast, errs[j].ast, opts).equal !== false) problems.push(`errors_collide:${errs[i].code}=${errs[j].code}`);
    }
    // the expected answer must satisfy its own form constraints
    for (const f of form) {
      if (!FORMS[f]) { problems.push(`unknown_form:${f}`); continue; }
      const v = FORMS[f](exp.ast, { flags: exp.flags, expected: exp.ast, unknown, opts });
      if (v.length) problems.push(`expected_violates_form:${f}:${v.join(',')}`);
    }

    function checkRaw(answer, aopts = {}) {
      const p = parse(answer, aopts.source || source);
      if (!p.ok) return { verdict: 'invalid', code: p.code, detail: p.detail };
      if (!isSol && hasRel(p.ast)) return { verdict: 'invalid', code: 'unsupported_operator', detail: 'relation' };
      const ansVal = strips ? solutionValue(p.ast, unknown) : p.ast;
      const r = solEq(ansVal, expVal, opts);
      if (r.equal === null) return { verdict: 'undetermined', reason: r.reason, method: r.method };
      if (r.equal) {
        const fv = [];
        for (const f of form) fv.push(...FORMS[f](p.ast, { flags: p.flags, expected: exp.ast, unknown, opts }));
        return fv.length ? { verdict: 'wrong_form', form_violations: [...new Set(fv)], method: r.method } : { verdict: 'correct', method: r.method };
      }
      const hits = errs.filter((e) => solEq(ansVal, e.ast, opts).equal === true).map((e) => e.code);
      if (hits.length) return { verdict: 'typical_error', error_codes: hits, method: r.method };
      return { verdict: 'wrong', method: r.method };
    }
    // Every result carries the normalized LaTeX that was graded (stored with the grading).
    function check(answer, aopts = {}) {
      const r = checkRaw(answer, aopts);
      const p = parse(answer, aopts.source || source);
      return p.ok ? { ...r, normalized: p.latex } : r;
    }
    return { problems, check, expected: exp };
  }

  return { parse, compile, valueEquivalent, normalizeInput, forms: Object.keys(FORMS), ce, version: CHECKER_VERSION };
}
