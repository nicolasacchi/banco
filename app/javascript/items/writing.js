// «Scrivi tu» (D-407): the small pure parts of the writing box, shared by writing_controller.js and its test.
//
//   countWords(text)       the words of a text, as the server counts them (WritingSubmission.count_words): runs of characters that are not space
//   check(text)            "empty" (nothing but space), "too_long" (more than TEXT_MAX characters) or null: the same refusals as the server's
//   draftKey(item, preview) the localStorage key of a draft: one per task (the item's key, so a new revision of the task keeps it); the teacher's preview
//                          has its own, so a draft of his never becomes the student's if they share a browser

export const TEXT_MAX = 4000
export const DRAFT_PREFIX = "banco.wdraft."

export function countWords(text) {
  const words = String(text ?? "").trim().split(/\s+/)
  return words.length === 1 && words[0] === "" ? 0 : words.length
}

export function check(text) {
  const clean = String(text ?? "").replace(/\r\n/g, "\n").trim()
  if (clean === "") return "empty"
  return clean.length > TEXT_MAX ? "too_long" : null
}

export const draftKey = (item, preview = false) => `${DRAFT_PREFIX}${preview ? "preview." : ""}${item}`
