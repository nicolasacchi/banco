// The vendored Compute Engine is pinned: exactly 0.146.0, with checksums (A-01).
// It is updated only together with the corpus and a comparison of raw outputs.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { version } from '../vendor/compute-engine/compute-engine.js';

const dir = new URL('../vendor/compute-engine/', import.meta.url);

test('Compute Engine is 0.146.0', () => {
  assert.equal(version, '0.146.0');
});

test('every vendored file matches SHA256SUMS', () => {
  const lines = readFileSync(new URL('SHA256SUMS', dir), 'utf8').split('\n').filter(Boolean);
  assert.ok(lines.length >= 4);
  for (const line of lines) {
    const [sum, file] = line.split(/\s+/);
    const actual = createHash('sha256').update(readFileSync(new URL(file, dir))).digest('hex');
    assert.equal(actual, sum, file);
  }
});
