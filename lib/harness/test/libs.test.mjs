// Tests of the two libraries a generator may import (/lib/rng.mjs, /lib/fmt.mjs).
// Run with: node --test 'lib/harness/test/*.test.mjs'

import test from "node:test";
import assert from "node:assert/strict";
import { makeRng } from "../rng.mjs";
import { it, signed, thousands, euro, frac, math, list } from "../fmt.mjs";

test("the same seed gives the same sequence, another seed another one", () => {
  const a = makeRng(42);
  const b = makeRng(42);
  const c = makeRng(43);
  const first = Array.from({ length: 20 }, () => a.next());
  assert.deepEqual(first, Array.from({ length: 20 }, () => b.next()));
  assert.notDeepEqual(first, Array.from({ length: 20 }, () => c.next()));
  assert.ok(first.every((x) => x >= 0 && x < 1));
});

test("int covers its range, both ends included", () => {
  const rng = makeRng(7);
  const seen = new Set();
  for (let i = 0; i < 500; i++) seen.add(rng.int(3, 6));
  assert.deepEqual([...seen].sort(), [3, 4, 5, 6]);
  assert.equal(makeRng(1).int(5, 5), 5);
});

test("pick, shuffle and sample use the seed and never change their input", () => {
  const items = [1, 2, 3, 4, 5, 6];
  const rng = makeRng(9);
  assert.ok(items.includes(rng.pick(items)));
  const shuffled = rng.shuffle(items);
  assert.deepEqual(items, [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...shuffled].sort(), items);
  assert.deepEqual(makeRng(9).shuffle(items), makeRng(9).shuffle(items));
  const some = makeRng(9).sample(items, 3);
  assert.equal(new Set(some).size, 3);
});

test("bool and sign", () => {
  const rng = makeRng(3);
  const signs = new Set(Array.from({ length: 50 }, () => rng.sign()));
  assert.deepEqual([...signs].sort(), [-1, 1]);
  assert.equal(makeRng(1).bool(1), true);
  assert.equal(makeRng(1).bool(0), false);
});

test("the generator object cannot be changed", () => {
  const rng = makeRng(1);
  assert.throws(() => {
    "use strict";
    rng.next = () => 0;
  });
});

test("fmt: the decimal comma, signs, thousands, euro", () => {
  assert.equal(it(3.5), "3,5");
  assert.equal(it(2, 2), "2,00");
  assert.equal(signed(3), "+3");
  assert.equal(signed(-3), "−3");
  assert.equal(signed(-2.5), "−2,5");
  assert.equal(thousands(1234567), "1.234.567");
  assert.equal(thousands(999), "999");
  assert.equal(thousands(-1500.5), "-1.500,5");
  assert.equal(euro(1234.5), "1.234,50");
  assert.equal(euro(7), "7,00");
});

test("fmt: fractions, mathematics and lists", () => {
  assert.equal(frac(3, 4), "\\frac{3}{4}");
  assert.equal(math("x+1"), "$x+1$");
  assert.equal(list(["a", "b", "c"]), "a, b e c");
  assert.equal(list(["a", "b"]), "a e b");
  assert.equal(list(["a"]), "a");
  assert.equal(list([]), "");
});
