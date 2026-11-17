// The practice page's actions all hang off the one base the view gives: S's own routes, or the teacher's preview (D-309).
import assert from "node:assert/strict"
import { test } from "node:test"
import { practiceUrls } from "../../../app/javascript/items/practice_urls.js"

test("S's page posts to /practice", () => {
  const urls = practiceUrls("/practice")
  assert.equal(urls.serve, "/practice/serves")
  assert.equal(urls.answer, "/practice/answers")
  assert.equal(urls.hint(75), "/practice/serves/75/hint")
  assert.equal(urls.solution(75), "/practice/serves/75/solution")
  assert.equal(urls.draft(75), "/practice/serves/75/draft")
  assert.equal(urls.contest(75), "/practice/serves/75/contest")
  assert.equal(urls.exercises("math.equations"), "/practice/exercises?topic=math.equations")
})

test("the teacher's preview page posts every action under /teacher/preview, hint, solution, draft and the list included", () => {
  const urls = practiceUrls("/teacher/preview/practice")
  assert.equal(urls.serve, "/teacher/preview/practice/serves")
  assert.equal(urls.answer, "/teacher/preview/practice/answers")
  assert.equal(urls.hint(75), "/teacher/preview/practice/serves/75/hint")
  assert.equal(urls.solution(75), "/teacher/preview/practice/serves/75/solution")
  assert.equal(urls.draft(75), "/teacher/preview/practice/serves/75/draft")
  assert.equal(urls.contest(75), "/teacher/preview/practice/serves/75/contest")
  assert.equal(urls.exercises("math.equations"), "/teacher/preview/practice/exercises?topic=math.equations")
  for (const url of [urls.serve, urls.answer, urls.hint(1), urls.solution(1), urls.draft(1), urls.contest(1), urls.exercises("t")]) assert.ok(url.startsWith("/teacher/preview/"), url)
})

test("a trailing slash on the base does not double", () => {
  assert.equal(practiceUrls("/practice/").hint(2), "/practice/serves/2/hint")
  assert.equal(practiceUrls("/practice/").draft(2), "/practice/serves/2/draft")
  assert.equal(practiceUrls("/practice/").contest(2), "/practice/serves/2/contest")
  assert.equal(practiceUrls("/practice/").exercises("a"), "/practice/exercises?topic=a")
})

test("a topic key is escaped in the list's address", () => {
  assert.equal(practiceUrls("/practice").exercises("a b&c"), "/practice/exercises?topic=a%20b%26c")
})
