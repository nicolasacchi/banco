// Poison input: an exponent written by the student must not hold the worker.
import test from 'node:test';
import assert from 'node:assert/strict';
import { checker } from './support.mjs';

const item = checker.compile({ expected: '3/4', form: [], errors: [] });

test('a huge decimal exponent is refused at once, not computed', () => {
  for (const raw of ['1e-99999999', '1e99999999', '2.5e+500', '0.1e-401']) {
    const t0 = performance.now();
    const r = item.check(raw, { source: 'text' });
    assert.ok(performance.now() - t0 < 1000, `${raw} took ${performance.now() - t0} ms`);
    assert.equal(r.verdict, 'invalid', raw);
  }
});

test('a reasonable exponent still reads as a number', () => {
  const r = checker.compile({ expected: '0.0000001', form: [], errors: [] }).check('1e-7', { source: 'text' });
  assert.equal(r.verdict, 'correct');
});

test('Italian thousands separator: 1.000 and 1.500.000 are invalid, 0.125 and 1,000 are not', () => {
  const one = checker.compile({ expected: '1', form: [], errors: [] });
  for (const raw of ['1.000', '2.500', '1.500.000', '12.345']) {
    const r = one.check(raw, { source: 'text' });
    assert.equal(r.verdict, 'invalid', raw);
  }
  assert.equal(one.check('1.000', { source: 'text' }).verdict, 'invalid');
  const eighth = checker.compile({ expected: '1/8', form: [], errors: [] });
  assert.equal(eighth.check('0.125', { source: 'text' }).verdict, 'correct');
  assert.equal(eighth.check('0,125', { source: 'text' }).verdict, 'correct');
});
