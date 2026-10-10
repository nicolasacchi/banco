// A small JSON Schema reader for the keywords of config/banco/schemas/diagram.json (draft 2020-12 subset:
// type, const, enum, required, properties, additionalProperties false, items, prefixItems, min/max of items,
// length and value, pattern, $ref into #/$defs, allOf, anyOf, if/then). It returns the first violation as
// { path, message } (path a JSON pointer) or null. Pure; the browser uses it so that a drawing never trusts
// data that Ruby would refuse.

function typeOf(value) {
  if (value === null) return "null"
  if (Array.isArray(value)) return "array"
  if (Number.isInteger(value)) return "integer"
  return typeof value
}

function typeMatches(want, value) {
  const got = typeOf(value)
  return want === got || (want === "number" && got === "integer")
}

export function validate(schema, data, root = schema) {
  return check(schema, data, "", root)
}

function resolve(ref, root) {
  const parts = ref.replace(/^#\//, "").split("/")
  return parts.reduce((node, key) => node[key], root)
}

function check(schema, value, path, root) {
  if (schema === true || schema === undefined) return null
  if (schema === false) return { path, message: "not allowed" }
  if (schema.$ref) {
    const error = check(resolve(schema.$ref, root), value, path, root)
    if (error) return error
  }
  if ("const" in schema && value !== schema.const) return { path, message: `must be ${schema.const}` }
  if (schema.enum && !schema.enum.includes(value)) return { path, message: "not one of the allowed values" }
  if (schema.type && !typeMatches(schema.type, value)) return { path, message: `must be a ${schema.type}` }
  const kind = typeOf(value)
  if (kind === "string") {
    if (schema.minLength !== undefined && [...value].length < schema.minLength) return { path, message: "too short" }
    if (schema.maxLength !== undefined && [...value].length > schema.maxLength) return { path, message: "too long" }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) return { path, message: "does not match the pattern" }
  }
  if (kind === "integer" || kind === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) return { path, message: "too small" }
    if (schema.maximum !== undefined && value > schema.maximum) return { path, message: "too large" }
  }
  if (kind === "array") {
    if (schema.minItems !== undefined && value.length < schema.minItems) return { path, message: "too few items" }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) return { path, message: "too many items" }
    const prefix = schema.prefixItems ?? []
    for (let i = 0; i < value.length; i++) {
      const sub = i < prefix.length ? prefix[i] : schema.items
      const error = check(sub, value[i], `${path}/${i}`, root)
      if (error) return error
    }
  }
  if (kind === "object") {
    for (const key of schema.required ?? []) {
      if (!(key in value)) return { path: `${path}/${key}`, message: "is required" }
    }
    const props = schema.properties ?? {}
    for (const key of Object.keys(value)) {
      if (key in props) {
        const error = check(props[key], value[key], `${path}/${key}`, root)
        if (error) return error
      } else if (schema.additionalProperties === false) {
        return { path: `${path}/${key}`, message: "is not a field of this type" }
      }
    }
  }
  for (const sub of schema.allOf ?? []) {
    if (sub.if) {
      if (!check(sub.if, value, path, root) && sub.then) {
        const error = check(sub.then, value, path, root)
        if (error) return error
      }
    } else {
      const error = check(sub, value, path, root)
      if (error) return error
    }
  }
  if (schema.anyOf && !schema.anyOf.some((sub) => !check(sub, value, path, root))) {
    return { path, message: "matches none of the allowed shapes" }
  }
  return null
}
