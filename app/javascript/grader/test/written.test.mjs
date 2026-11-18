// Answers written in full (D-362): «x = 37/5», «√(…) = 24a³», chains «a = b = c». The shared vectors (expr-written-*) cover the
// verdicts; these pin the splitting at the top-level `=`, the left sides that are accepted and the ones that never are.
import test from 'node:test';
import assert from 'node:assert/strict';
import { checker, stemsOf } from './support.mjs';
import { splitEquals } from '../checker.mjs';

const item = (expected, extra = {}) => checker.compile({ expected, ...extra });
const verdict = (it, raw, source = 'text') => it.check(raw, { source }).verdict;

test('splitEquals cuts at the top-level equals sign only', () => {
  assert.deepEqual(splitEquals('x = 37/5'), ['x', '37/5']);
  assert.deepEqual(splitEquals('a=b=c'), ['a', 'b', 'c']);
  assert.deepEqual(splitEquals('\\frac{a=b}{c} = 2'), ['\\frac{a=b}{c}', '2']);
  assert.deepEqual(splitEquals('(x=2)'), null);
  for (const t of ['x', 'x<=3', 'x>=3', 'x!=3', 'x==3', 'x=', '=3', 'x = = 3', '(x=3', 'x=3)']) assert.equal(splitEquals(t), null, t);
});

test('the stems of a vector item: the math between dollars, or plain arithmetic', () => {
  assert.deepEqual(stemsOf({ display: { stem_it: 'Semplifica $\\sqrt{8}$ e $2+3$' } }), ['\\sqrt{8}', '2+3']);
  assert.deepEqual(stemsOf({ display: { stem_it: '12 : 3 − 1' } }), ['12 : 3 − 1']);
  assert.deepEqual(stemsOf({ prompt: { stem_it: 'Semplifica l\'espressione.' }, display: {} }), []);
});

test('a letter on the left is the unknown only when the key is a number or the item names the unknown', () => {
  const number = item('\\frac{37}{5}');
  for (const raw of ['x = 37/5', 'x=37/5', 'x = 7,4', 'k = 7.4']) assert.equal(verdict(number, raw), 'correct', raw);
  assert.equal(verdict(number, 'x = 37/4'), 'wrong');
  assert.equal(verdict(item('2x+4'), 'y = 2x+4'), 'undetermined');
  const named = item('2x+4', { unknown: 'y', form: ['isolate'] });
  assert.equal(verdict(named, 'y = 2x+4'), 'correct');
});

test('the left side repeats the expression shown, as a tree: spacing, signs and brackets do not matter, another expression does', () => {
  const it = item('24a^3', { stems: ['\\sqrt{625a^6-49a^6}'] });
  for (const raw of ['√(625a⁶ − 49a⁶) = 24a³', '\\sqrt{625a^6-49a^6}=24a^3', 'sqrt(625a^6-49a^6) = 24a^3', '√((625a⁶ − 49a⁶)) = 24a³']) {
    assert.equal(verdict(it, raw), 'correct', raw);
  }
  assert.equal(verdict(it, '√(625a⁶ + 49a⁶) = 24a³'), 'undetermined');
  assert.equal(verdict(it, '√(625a⁶ − 49a⁶) = 24a²'), 'wrong');
});

test('an equation shown is not an expression: its left side is never accepted', () => {
  const it = item('3', { stems: ['x+2=5'] });
  assert.equal(verdict(it, 'x+2 = 3'), 'undetermined');
  assert.equal(verdict(it, 'x = 3'), 'correct');
});

test('a chain is graded on its last member only when every member equals the key', () => {
  const it = item('24a^3', { stems: ['\\sqrt{625a^6-49a^6}'] });
  assert.equal(verdict(it, '√(625a⁶ − 49a⁶) = √(576a⁶) = 24a³'), 'correct');
  assert.equal(verdict(it, '√(625a⁶ − 49a⁶) = √(500a⁶) = 24a³'), 'wrong');
  assert.equal(verdict(it, '√(625a⁶ − 49a⁶) = √(576a⁶) = 24a²'), 'wrong');
  const sum = item('7');
  assert.equal(verdict(sum, '3+4 = 7 = 7'), 'correct');
  assert.equal(verdict(sum, '3+5 = 7 = 7'), 'wrong');
  assert.equal(verdict(sum, 'x = 3+4 = 7'), 'correct');
  assert.equal(verdict(sum, 'x = 3+5 = 7'), 'wrong');
});

test('the value keeps its own rules: errors, forms, a percent sign, an unreadable member', () => {
  const errors = [{ code: 'denominator_slip', latex: '\\frac{37}{4}' }];
  assert.deepEqual(item('\\frac{37}{5}', { errors }).check('x = 37/4', { source: 'text' }).error_codes, ['denominator_slip']);
  const forms = item('2\\sqrt{2}', { form: ['radical_simplified'] }).check('x = \\sqrt{8}', { source: 'mathlive' });
  assert.deepEqual([forms.verdict, forms.form_violations], ['wrong_form', ['radicand_not_reduced']]);
  assert.equal(verdict(item('\\frac{9}{20}'), 'x = 45%'), 'correct');
  const bad = item('5').check('x = 5 2', { source: 'text' });
  assert.deepEqual([bad.verdict, bad.code], ['invalid', 'ambiguous_digit_space']);
});

test('what is graded is the last member: its normalized form is stored', () => {
  assert.equal(item('\\frac{37}{5}').check('x=\\frac{37}{5}', { source: 'mathlive' }).normalized, '\\frac{37}{5}');
});

test('a solution or an isolated letter still reads «x = value»; a chain needs its steps to equal the value', () => {
  const solution = item('x=3', { form: ['solution'], unknown: 'x' });
  assert.equal(verdict(solution, 'x = 3'), 'correct');
  assert.equal(verdict(solution, 'x = 6/2 = 3'), 'correct');
  assert.equal(verdict(solution, 'x = 4 = 3'), 'wrong');
});
