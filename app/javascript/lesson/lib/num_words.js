// NumWords: An Italian amount in words, as written on a cheque, with its accepted variants and the typical wrong ones.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T8): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/num_words.rb and both run test/fixtures/lesson2/amount_words.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "amount": "amount(text)",
  "variants": "variants(text)",
  "wrong_forms": "wrongForms(text)"
}

// The canonical words of an amount ('1240,50' is 'milleduecentoquaranta/50').
export const amount = notBuilt("num_words.amount", "T8", "w2-2")
// The forms a grader accepts for an amount.
export const variants = notBuilt("num_words.variants", "T8", "w2-2")
// The typical wrong forms, by name.
export const wrongForms = notBuilt("num_words.wrongForms", "T8", "w2-2")
