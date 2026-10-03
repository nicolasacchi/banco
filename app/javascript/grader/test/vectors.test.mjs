// The expression vectors of test/fixtures/grading/vectors.json (the Ruby tests
// run the same file through Grading, closed components included).
import test from 'node:test';
import assert from 'node:assert/strict';
import { checker, readVectors, specFromVector } from './support.mjs';

const vectors = readVectors();
const expression = vectors.cases.filter((c) => c.component === 'expression');

test('the vectors file has expression cases', () => {
  assert.ok(expression.length >= 15, `only ${expression.length} expression vectors`);
});

for (const c of expression) {
  test(`vector ${c.id}`, () => {
    const item = checker.compile(specFromVector(c.item));
    assert.deepEqual(item.problems, []);
    const got = item.check(c.raw, { source: c.source || 'mathlive' });
    assert.equal(got.verdict, c.expect.verdict);
    if (c.expect.error_codes) assert.deepEqual([...got.error_codes].sort(), [...c.expect.error_codes].sort());
    if (c.expect.form_violations) assert.deepEqual([...got.form_violations].sort(), [...c.expect.form_violations].sort());
    // The registry name of an invalid answer (invalid_code) is mapped on the Ruby side.
    if (c.expect.method) assert.equal(String(got.method).startsWith('exact') ? 'exact' : 'float', c.expect.method);
  });
}
