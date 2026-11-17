// The address of an icon sprite (D-347). public/ is served with a one-year cache, so a sprite at a fixed URL never reaches a
// browser that already has it: the address carries `?v=` and the first 12 hex digits of the sprite's SHA-256
// (lesson/sprites.js, written by bin/build-icons; Banco::Sprites does the same for the server's pages).
import versions from "lesson/sprites"

export const SPRITE_DIR = "/vendor/lucide@1.54.0/"
export const MAIN_SPRITE = "banco-sprite.svg"

// "/vendor/lucide@1.54.0/banco-sprite.svg?v=438f981bb785"
export const spriteUrl = (file = MAIN_SPRITE) => {
  const version = versions[file]
  if (!version) throw new Error(`no version for the sprite ${file}`)
  return `${SPRITE_DIR}${file}?v=${version}`
}
