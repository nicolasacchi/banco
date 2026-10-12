// Dates: Calendar dates as ISO strings: day counts, due dates and the commercial year fraction.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T8): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/dates.rb and both run test/fixtures/lesson2/dates.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "add_days": "addDays(date, days, start)",
  "diff": "diff(from, to, convention)",
  "due": "due(date, daysAfter)",
  "year_fraction": "yearFraction(days, year)"
}

// The date after +days+ days; the start day is excluded (the default) or included.
export const addDays = notBuilt("dates.addDays", "T8", "w2-2")
// Days between two dates, actual or commercial (30/360).
export const diff = notBuilt("dates.diff", "T8", "w2-2")
// The due date of 'a N giorni data'.
export const due = notBuilt("dates.due", "T8", "w2-2")
// days / 360 or days / 365 as an exact fraction.
export const yearFraction = notBuilt("dates.yearFraction", "T8", "w2-2")
