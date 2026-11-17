// D-347: an icon's address carries the version of its sprite, so a changed sprite is a new URL (public/ is cached for a year).
import "./setup.mjs"
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const { spriteHref } = await import("lesson/dom")
const { spriteUrl } = await import("lesson/sprite")
const digest = (file) => createHash("sha256").update(readFileSync(new URL(`../../../../public/vendor/lucide@1.54.0/${file}`, import.meta.url))).digest("hex").slice(0, 12)

test("the structural sprite's address ends with the first 12 hex digits of its SHA-256", () => {
  assert.equal(spriteUrl(), `/vendor/lucide@1.54.0/banco-sprite.svg?v=${digest("banco-sprite.svg")}`)
  assert.equal(spriteHref("lightbulb"), `/vendor/lucide@1.54.0/banco-sprite.svg?v=${digest("banco-sprite.svg")}#lightbulb`)
})

test("an icon of a subject's own list points to that subject's sprite, with its version", () => {
  assert.equal(spriteHref("dna"), `/vendor/lucide@1.54.0/banco-sprite-biology.svg?v=${digest("banco-sprite-biology.svg")}#dna`)
})

test("an icon in no list falls back to the structural sprite", () => {
  assert.match(spriteHref("no-such-icon"), /banco-sprite\.svg\?v=[0-9a-f]{12}#no-such-icon$/)
})

test("a sprite with no version is an error, never a bare address", () => {
  assert.throws(() => spriteUrl("banco-sprite-nowhere.svg"), /no version/)
})
