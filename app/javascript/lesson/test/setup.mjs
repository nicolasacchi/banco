// The lesson modules import each other by importmap names ("lesson/num", "items/markup", "katex"), as in
// the browser. This maps the same names to files for node. A test file does `import "./setup.mjs"` first
// and then imports the module under test with `await import("lesson/...")` (static imports are linked
// before this file runs).
import { registerHooks } from "node:module"
import { existsSync } from "node:fs"
import { pathToFileURL } from "node:url"

const root = new URL("../../../../", import.meta.url)

registerHooks({
  resolve(specifier, context, nextResolve) {
    let file
    if (specifier === "katex") file = new URL("public/vendor/katex@0.19.0/katex.mjs", root)
    else if (/^(lesson|items)\//.test(specifier)) file = new URL(`app/javascript/${specifier}.js`, root)
    if (file && existsSync(file)) return { url: pathToFileURL(file.pathname).href, shortCircuit: true }
    return nextResolve(specifier, context)
  }
})
