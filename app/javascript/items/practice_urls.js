// The addresses of a practice page's actions, all from the one base the view gives (spath("/practice"): "/practice" for S,
// "/teacher/preview/practice" in the teacher's preview, D-309). A page never writes "/practice" itself, so the preview
// cannot post to the student's own routes.
export function practiceUrls(base) {
  const root = String(base).replace(/\/+$/, "")
  return {
    serve: `${root}/serves`,
    answer: `${root}/answers`,
    hint: (serveId) => `${root}/serves/${serveId}/hint`,
    solution: (serveId) => `${root}/serves/${serveId}/solution`
  }
}
