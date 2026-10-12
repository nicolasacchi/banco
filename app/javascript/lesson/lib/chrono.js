// Chrono: Years without a year 0, centuries and Roman numerals. A year is an integer string, negative = a.C.; '0' is refused.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T4a): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/chrono.rb and both run test/fixtures/lesson2/chrono.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "duration": "duration(from, to)",
  "century": "century(year)",
  "roman": "roman(n)",
  "parse_roman": "parseRoman(text)",
  "mutants": "mutants(from, to)"
}

// Whole years from one year to the other, the year 0 not counted: -27 to 14 is 40.
export const duration = notBuilt("chrono.duration", "T4a", "w2-1")
// The Italian label of a year's century: 'II secolo a.C.'.
export const century = notBuilt("chrono.century", "T4a", "w2-1")
// A positive integer below 4000 as a Roman numeral.
export const roman = notBuilt("chrono.roman", "T4a", "w2-1")
// A Roman numeral as an integer, nil when it is not one.
export const parseRoman = notBuilt("chrono.parseRoman", "T4a", "w2-1")
// The wrong values of duration that a typical error gives (year 0 counted, eras subtracted, same era added), by name.
export const mutants = notBuilt("chrono.mutants", "T4a", "w2-1")
