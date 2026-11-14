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
})

test("the teacher's preview page posts every action under /teacher/preview, hint and solution included", () => {
  const urls = practiceUrls("/teacher/preview/practice")
  assert.equal(urls.serve, "/teacher/preview/practice/serves")
  assert.equal(urls.answer, "/teacher/preview/practice/answers")
  assert.equal(urls.hint(75), "/teacher/preview/practice/serves/75/hint")
  assert.equal(urls.solution(75), "/teacher/preview/practice/serves/75/solution")
  for (const url of [urls.serve, urls.answer, urls.hint(1), urls.solution(1)]) assert.ok(url.startsWith("/teacher/preview/"), url)
})

test("a trailing slash on the base does not double", () => {
  assert.equal(practiceUrls("/practice/").hint(2), "/practice/serves/2/hint")
})
