// The 3,524-pair corpus (synthetic): every verdict must match the label.
import test from 'node:test';
import assert from 'node:assert/strict';
import { checker, readCorpus } from './support.mjs';

const pairs = readCorpus();
const compiled = new Map();
function itemFor(p) {
  if (!compiled.has(p.item)) {
    compiled.set(p.item, checker.compile({ expected: p.expected, form: p.form, errors: p.errors, unknown: p.unknown, domain: p.domain }));
  }
  return compiled.get(p.item);
}

test('the corpus has the 3,524 labelled pairs', () => {
  assert.equal(pairs.length, 3524);
});

test('every generated item compiles clean', () => {
  for (const p of pairs) {
    if (p.cat === 'invalid_input') continue;
    const item = itemFor(p);
    assert.deepEqual(item.problems, [], `${p.item}: ${item.problems}`);
  }
});

test('0 false accepts, 0 false rejects, every verdict and error code as labelled', () => {
  let falseAccept = 0;
  let falseReject = 0;
  const mismatch = [];
  for (const p of pairs) {
    const got = itemFor(p).check(p.answer, { source: p.source });
    const valueEqual = got.verdict === 'correct' || got.verdict === 'wrong_form';
    if (p.truth.invalid !== true) {
      if (valueEqual && p.truth.equal === false) falseAccept++;
      if (!valueEqual && p.truth.equal === true) falseReject++;
    }
    const codesOk = got.verdict !== 'typical_error' ||
      JSON.stringify([...got.error_codes].sort()) === JSON.stringify([...p.truth.error_codes].sort());
    if (got.verdict !== p.expected_verdict || !codesOk) mismatch.push({ id: p.id, answer: p.answer, expected: p.expected_verdict, got });
  }
  assert.equal(falseAccept, 0, 'false accepts');
  assert.equal(falseReject, 0, 'false rejects');
  assert.deepEqual(mismatch.slice(0, 5), [], `${mismatch.length} verdict mismatches`);
});

test('the checker is deterministic: a second pass gives the same verdicts', () => {
  const pass = () => pairs.filter((_, i) => i % 5 === 0).map((p) => JSON.stringify(itemFor(p).check(p.answer, { source: p.source })));
  assert.deepEqual(pass(), pass());
});
