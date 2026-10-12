// What a climograph computes (T6, WAVE2 2.4): the arid months by Bagnouls-Gaussen (P <= 2T), the annual total, the annual mean, the warmest and the
// coldest month and the range. Exact numbers; none of it is author data (1.1). The Ruby twin is Lessons::Diagrams::Climograph.stats; both run
// test/fixtures/lesson2/climate.json.
import * as N from "lesson/num"

export const MONTHS = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
export const ABBR = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"]
export const INITIALS = ["G", "F", "M", "A", "M", "G", "L", "A", "S", "O", "N", "D"]

// temp and precip: twelve exact numbers each (lesson/num). Months are 1..12.
export function stats(temp, precip) {
  let hi = 0
  let lo = 0
  for (let i = 1; i < 12; i++) {
    if (N.compare(temp[i], temp[hi]) > 0) hi = i
    if (N.compare(temp[i], temp[lo]) < 0) lo = i
  }
  const arid = []
  for (let i = 0; i < 12; i++) if (N.compare(precip[i], N.mul(N.int(2), temp[i])) <= 0) arid.push(i + 1)
  const sum = (list) => list.reduce((a, b) => N.add(a, b), N.int(0))
  return { arid, total: sum(precip), mean: N.div(sum(temp), N.int(12)), warmest: hi + 1, coldest: lo + 1, range: N.sub(temp[hi], temp[lo]), tmax: temp[hi], tmin: temp[lo] }
}

// "da gennaio a maggio, novembre e dicembre": runs of three or more months as "da ... a ...".
export function monthList(months) {
  const parts = []
  for (let i = 0; i < months.length; ) {
    let j = i
    while (j + 1 < months.length && months[j + 1] === months[j] + 1) j++
    if (j - i >= 2) parts.push(`da ${MONTHS[months[i] - 1]} a ${MONTHS[months[j] - 1]}`)
    else for (let k = i; k <= j; k++) parts.push(MONTHS[months[k] - 1])
    i = j + 1
  }
  return parts.length <= 1 ? parts.join("") : `${parts.slice(0, -1).join(", ")} e ${parts[parts.length - 1]}`
}
