// The theme in force for a choice (D-350). The student's choices are cream, light, dark and auto; the stylesheets know the first three, so
// "auto" (follow the device) is settled here from prefers-color-scheme: cream by day, dark by night. The same rule is in
// app/views/shared/_theme_script.html.erb, which runs in the head of a page before it is painted.
export function resolveTheme(choice) {
  if (choice !== "auto") return choice
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "cream"
}

// Puts a choice on an element (<html> or the teacher's box): data-theme-choice is what the student picked, data-theme what the page shows.
export function applyTheme(element, choice) {
  element.dataset.themeChoice = choice
  element.dataset.theme = resolveTheme(choice)
}
