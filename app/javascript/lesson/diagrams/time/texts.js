// The Italian words of the time family that a layout or a description prints. The locale file config/locales/lesson_time.it.yml holds the
// same strings (key `scene`), the Ruby twins read them from there, and time_texts.test.mjs fails when the two differ.
// Short sentences, common words: the student reads with difficulty. `%{name}` marks a place for a value (see fill).
export const TEXT = {
  before: "prima",
  now: "adesso",
  after: "dopo",
  era_bc: "a.C.",
  era_ad: "d.C.",
  year_one: "anno",
  year_many: "anni",
  about: "circa",
  note_hint: "Tocca il punto per leggere la nota.",
  measure_label: "Quanti anni passano?",
  measure_hint: "Tocca due nomi.",
  measure_pick: "Scegli due fatti per vedere quanti anni passano.",
  measure_too_many: "Hai scelto più di due fatti. Toglierne uno.",
  measure_result: "Tra %{a} e %{b} passano %{n}.",
  years_intro: "Linea del tempo dal %{from} al %{to}.",
  period_line: "%{label}: dal %{from} al %{to}.",
  event_line: "%{year}: %{label}.",
  span_line: "Da %{a} a %{b} passano %{n}.",
  span_open: "Una parentesi va da %{a} a %{b}.",
  centuries_line: "Secoli: %{list}.",
  lane_line: "Riga %{label}.",
  tense_intro: "Una linea dell'ordine: prima, adesso, dopo.",
  mark_point: "un momento %{at}",
  mark_range: "dura da %{at} a %{to}",
  mark_habit: "succede di solito",
  mark_plan: "è deciso %{from} e succede %{at}",
  mark_uncertain: "forse",
  rel_before: "prima di adesso",
  rel_now: "adesso",
  rel_after: "dopo adesso",
  neutral_point: "un punto",
  legend_title: "Che cosa vuol dire"
}

export const fill = (template, vars = {}) => template.replace(/%\{(\w+)\}/g, (_, k) => String(vars[k]))
