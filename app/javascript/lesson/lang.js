// The language of a lesson's text (D-265; the Ruby twin is Lessons::Lang). In a lesson of a language subject a colour role span holds words of
// that language unless it says |it, so the parser is told which. Keys and spans of a language belong to the subjects that teach it (the server
// checks that, E-LESSON-LANG); the browser only needs the target of the subject.
export const TARGET_OF = {"english": "en", "spanish": "es"}

export const targetOf = (subject) => TARGET_OF[subject] ?? null
