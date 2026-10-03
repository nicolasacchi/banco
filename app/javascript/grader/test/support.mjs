// Shared by the grader tests: a checker over the vendored Compute Engine, and
// the paths of the shared fixtures (test/fixtures/grading/).
import { readFileSync } from 'node:fs';
import { ComputeEngine } from '../vendor/compute-engine/compute-engine.js';
import { createChecker } from '../checker.mjs';

const fixtures = new URL('../../../../test/fixtures/grading/', import.meta.url);

export const checker = createChecker({ ComputeEngine });
export const readCorpus = () =>
  readFileSync(new URL('corpus.jsonl', fixtures), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const readVectors = () => JSON.parse(readFileSync(new URL('vectors.json', fixtures), 'utf8'));

// Item spec of the vectors file (banco.item/1 field names) -> checker.compile spec.
export function specFromVector(item) {
  const answer = item.answer;
  const latex = typeof answer === 'string' ? answer : answer.latex;
  return {
    expected: latex,
    form: item.form || [],
    errors: (item.errors || []).map((e) => ({ code: e.code, latex: typeof e.value === 'string' ? e.value : e.value.latex })),
    unknown: (typeof answer === 'object' && answer.unknown) || null,
    domain: (typeof answer === 'object' && answer.domain) || {},
  };
}
