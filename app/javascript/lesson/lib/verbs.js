// Verbs: english/verbs lookups and the contraction table.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T3): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/verbs.rb and both run test/fixtures/lesson2/verbs.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "lookup": "lookup(base)",
  "family_mark": "familyMark(verb)",
  "expand_contractions": "expandContractions(text)"
}

// A verb of english/verbs: base, past and participle variants.
export const lookup = notBuilt("verbs.lookup", "T3", "w2-1")
// The mark of a verb in its family: same_forms, vowel, participle_from_base, participle_from_past.
export const familyMark = notBuilt("verbs.familyMark", "T3", "w2-1")
// A text with its contractions expanded (english/contractions), for both sides of a typed answer.
export const expandContractions = notBuilt("verbs.expandContractions", "T3", "w2-1")
