// Words: The split notation shared by paradigm and word_parts (| stem and ending, [..] changed letters, + attached piece), Spanish syllables and stress.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T3): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/words.rb and both run test/fixtures/lesson2/spanish_words.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "split": "split(notation)",
  "syllables_es": "syllablesEs(word)",
  "stress_es": "stressEs(word)",
  "tilde_ok": "tildeOk(word)",
  "present": "present(verb, pattern)"
}

// A form in split notation as pieces with their marks; the marks removed give the word.
export const split = notBuilt("words.split", "T3", "w2-1")
// The syllables of a Spanish word.
export const syllablesEs = notBuilt("words.syllablesEs", "T3", "w2-1")
// The 1-based index of the stressed syllable.
export const stressEs = notBuilt("words.stressEs", "T3", "w2-1")
// Whether the written tilde (or its absence) follows the stress rule.
export const tildeOk = notBuilt("words.tildeOk", "T3", "w2-1")
// W2-2: the six present forms by pattern; spanish/verbs is the truth and the engine only cross-checks regular and stem-changing rows.
export const present = notBuilt("words.present", "T3", "w2-1")
