// The body of a library function that its track has not built yet (WAVE2 1.10). It throws, so nothing can use an answer that was never computed.
export class NotBuilt extends Error {}

export function notBuilt(name, track, batch) {
  return (..._args) => {
    throw new NotBuilt(`${name} is not built yet (${track}, ${batch})`)
  }
}
