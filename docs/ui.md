# The interface: tokens and components (D-306)

One look for every page, the lessons' (lesson/2): rounded cards, a soft shadow, icons, one primary action, calm colour. The
teacher's pages use the same parts, only denser. Behaviour, routes and privacy do not change with the look.

Files: the tokens are at the top of `app/assets/stylesheets/application.css` (beside the two themes, `cream` and `dark`);
the components are `app/assets/stylesheets/components.css`; the helpers are `app/helpers/ui_helper.rb`; icons are
`config/banco/icons.yml` (`ui` list) built by `bin/build-icons` (CI runs `--check`). `lesson*.css` keeps its own em scale
inside `.l2`; do not use its classes outside a lesson.

## Rules

- Use a token, never a raw value: `var(--space-4)`, `var(--radius-m)`, `var(--text-s)`, `var(--tone-error)`.
- A target is at least 44 px (`--tap` or `--tap-small`). A label is centred. A row of buttons has equal heights.
- State is a word, then an icon, then a colour. Never colour alone. No red and green for right and wrong: use `success`
  (teal), `nearly` (brass), `error` (rust) and `hint` (violet), which are the lessons' roles.
- No text under 0.9 rem, nothing wider than the screen at 390 px, no `!important` (the one allowed place is reduced motion).
- Motion reads `--dur-1`, `--dur-2` and `--ease`; reduced motion sets them to 0.
- Student texts and teacher texts are Italian; classes, keys and routes are English.

## Tokens

| Group | Names |
|---|---|
| Colour (per theme) | `--bg --text --muted --line --primary --primary-text --surface --focus --soft-primary` |
| Tones (from the lessons' roles) | `--tone-info --tone-success --tone-nearly --tone-error --tone-hint --tone-muted` |
| Space (a 5 px step) | `--space-1` 0.25 rem, `-2` 0.5, `-3` 0.75, `-4` 1, `-5` 1.5, `-6` 2, `-7` 3, `-8` 4 |
| Type | `--text-s` 0.9, `--text-m` 1, `--text-l` 1.15, `--text-h2` 1.4, `--text-h1` 1.75, `--text-display` 2.25 (rem); `--leading-tight`, `--leading-body` |
| Shape | `--radius-s` 0.35 rem, `--radius-m` 0.7, `--radius-l` 1.2, `--radius-pill`; `--border` (2 px), `--border-soft` (1 px) |
| Depth | `--shadow-1` (a card), `--shadow-2` (a raised card, a dialog) |
| Targets and focus | `--tap` 2.75 rem, `--tap-small` 2.25 rem, `--focus-ring`, `--focus-offset` |
| Motion | `--dur-1` 120 ms, `--dur-2` 240 ms, `--ease` |

The size the student chooses is the root size: Minimo 12 px, Piccolissimo 14, Molto piccolo 16, Piccolo 18, Normale 20 (the default), Grande 24, Molto grande 28
(`html[data-size]`). Every length of a page is in rem (or em of it), never px (a border or a hairline aside), so a size scales the text, the
gaps, the cards, the buttons and the icons together (D-350). Media queries stay in px or rem of the browser (the window, not the size).

Targets: `--tap` and `--tap-small` are 2.75 and 2.25 rem; on a touch screen (`pointer: coarse`) they are `max(that, 44px)`, so a finger always has
44 CSS px, also at 12 px. A lesson does the same in the last block of `lesson.css`. With a mouse a target follows the size.

A desktop (a window of 1000 px or more, `pointer: fine`) is tighter on the student's pages: `student_scale.css` redefines the spacing, headings,
radii and targets under `body.student` (a fifth smaller), makes the page 52 rem wide (`--page-w`, 70 ch elsewhere) and lays lists of cards in a grid
(Oggi, Materie, the topics of a subject, the steps of a topic). A phone, a narrow window and the teacher's pages keep the single column.

Themes: `cream` (the default), `light` (white, neutral), `dark` and `auto`. `<html>` has `data-theme` (cream, light or dark: what is shown) and
`data-theme-choice` (what the student picked). For `auto` the head of the layout runs `shared/_theme_script` before the first paint: cream when the
device is light, dark when it is dark, and again when the device changes; the lesson's own dialog does the same with `lesson/theme.js`. Colour in CSS
comes from the variables of the palette, never from a theme name; the lesson roles of `light` are the cream ones (they have more contrast on white).

## Components

Each block: the classes, when to use it, one example.

### Icons
`<%= ui_icon("circle-check") %>` draws a Lucide icon from `banco-sprite.svg` (decorative, `aria-hidden`; the words next to it
carry the meaning). `css: "big"` makes it 2.5 rem. The names are the keys of `icons.yml` (`structural` and `ui`). A new icon
is a line in `icons.yml` (its Lucide file copied under `public/vendor/lucide@1.54.0/icons/`) and `bin/build-icons`. Every sprite address carries `?v=` and the first 12 hex digits of the file's SHA-256 (`Banco::Sprites`, D-347), because `public/` is cached for a year.
The `ui` names for pages: `back alert empty loading locked not-found check close info prev next expand menu`.

### Button
`.button` is primary (one per screen area). `.secondary` is the second choice, `.text` a quiet text action, `.danger` a
destructive one (always behind a confirm), `.small` a denser one (still 45 px), `.block` full width. Works on `<a>`,
`<button>` and `<input type=submit>`. Put several in `.button-row` (wraps, equal heights; `.end` right-aligns; a `form`
around a button stretches too).
```erb
<div class="button-row">
  <a class="button" href="/today">Continua</a>
  <a class="button secondary" href="/subjects">Materie</a>
</div>
```

### Card
`.card` for a unit of content; `.card.action` for the one thing to do now; `.cards` lays several out in a grid that never
overflows. A heading row is a `.cluster` with `h2.card-title` and a pill.
```erb
<article class="card">
  <div class="cluster"><h2 class="card-title">Equazioni</h2><%= ui_pill("In corso", :info) %></div>
  <p>Due passi, circa 20 minuti.</p>
</article>
```

### List row, clickable as a whole
`ul.row-list > li.row` with `a.row-stretch` inside (the link covers the whole row), or `a.row` directly when the row is
only a link. Parts: `.row-main`, `.row-title`, `.row-meta`, `.row-end` (a pill, a chevron). Use it for topics, subjects,
search hits and every list where each item opens a page.
```erb
<ul class="row-list"><li class="row">
  <div class="row-main"><a class="row-stretch" href="/topics/x">Equazioni di primo grado</a><span class="row-meta">20 minuti</span></div>
  <span class="row-end"><%= ui_pill("Da fare", :muted) %><%= ui_icon("next") %></span>
</li></ul>
```

### Tag and state pill
`ui_tag("12 minuti")` is a quiet label or a count. `ui_pill(text, tone, icon:)` is a state: tone `info success nearly error
hint muted`, the word first, an icon only if it adds meaning. The same two classes (`.tag`, `.pill.success`) work in plain HTML.
```erb
<%= ui_pill("Approvata", :success, icon: "circle-check") %>
```

### Notice
`ui_notice(kind, text, title:)` or with a block; kinds `info success nearly error hint`. An error is `role="alert"`, the
others `role="status"`. The old `<p class="notice">` still works (no icon); `.notice.alert` is the error tone.
```erb
<%= ui_notice :nearly, "Quasi giusto: manca il segno.", title: "Quasi" %>
```

### Dialog
`<dialog class="dialog">` with `.dialog-head`, `.dialog-body` (the only part that scrolls) and `.dialog-actions` (always
visible). At 600 px or less it is a bottom sheet; it is never wider than the screen. Open with `showModal()`; Escape and
the backdrop close it. Do not restyle `#comment-box` here: the comments page owns it, but it may use these parts.
```html
<dialog class="dialog" aria-labelledby="t1"><div class="dialog-head"><h2 id="t1">Titolo</h2></div>
  <div class="dialog-body">...</div><div class="dialog-actions"><button class="button">Invia</button><button class="button secondary">Annulla</button></div></dialog>
```

### Form fields
`.form-field` holds a visible `label` (never a placeholder as a label), the control, `.field-help` and `.field-error`. Inputs,
selects and textareas are styled by default (44 px, rounded, the focus ring); `.input` is the explicit class. Radios and
checkboxes use the app's colours; a `label` around one is a 44 px target anywhere outside a lesson. `.choice` is a card-like
row for a radio or checkbox (checked state outlined), several in a `fieldset.choice-list`.
```erb
<fieldset class="choice-list"><legend>Colori</legend>
  <label class="choice"><input type="radio" name="theme" value="cream" checked> Crema</label>
</fieldset>
```

### Page header
`ui_page_header("Titolo", back: ["Materie", "/subjects"], sub: "...") { buttons }`: one back link (never two ways back), the
h1, actions on the right, a line under it.

### Table wrapper
Wrap every table wider than a phone: `ui_table_wrap(label: "Sedute") { <table class="data">... }`. It scrolls inside, takes
keyboard focus and never widens the page. Add `class="data stack"` and `data-label` on each `td` to turn rows into blocks below 40 rem.

### Disclosure
`<details class="disclosure"><summary>Come si risponde</summary>...</details>` is a 44 px bar with a chevron. Any plain `summary`
also gets 44 px of height. Use it for help lines and for raw data that the teacher rarely needs.

### Empty, loading, error pages
`ui_empty("Nessun commento", action: ["Vai a Oggi", "/today"])`: an icon, one sentence, one next action (never an empty
heading: hide the group instead). `ui_loading("Sto correggendo")` is a polite status line. 403 and 404 are
`shared/error.html.erb` through `render_error(:forbidden | :not_found)` in `ApplicationController`; the text is the same for
everyone and the status code is unchanged. The static `public/{400,404,422,500}.html` match.

### Meter and dots
`ui_meter(40, "Avanzamento")` is a bar; `<span class="dots"><span class="on"></span><span></span></span>` shows n of m.

### Time
`ui_time(value)` writes "2 nov 2026, 09:00" (Rome time); `ui_time(value, time: false)` only the date. Never print an ISO string.

## What the next slices do

Student shell, Oggi, practice and the sitting (slices 3 to 5) and the teacher's pages (6 to 8) compose these parts; a missing
part is added here first (CSS, helper, this page), then used. Do not add page-specific copies of a button, card or notice.
Check each page at 390 and 1280 px, in cream and dark, and at the largest text size.

## The student's pages (D-307, slices 3 to 5)

Styles are in `app/assets/stylesheets/student.css` (class names no teacher page uses); helpers in `app/helpers/student_ui_helper.rb`.
No shared component was added to `components.css`.

- **Top bar** (`shared/_student_menu`): `header.topbar` with the section name, «Commenta» (`#comment-open-menu`) and «Menu», which opens
  `dialog#student-menu-dialog` (`student_menu_controller.js`) holding `nav.student-menu` as shared rows. In a sitting the bar is
  «Pausa: torna a Oggi» and «Commenta». A page with its own bar (lesson/2) hides it. Below 34 rem the title is hidden; below 15 rem
  (largest text on a phone) the two buttons show the icon only and keep their words for a screen reader.
- **Subject chip and card**: `subject_chip(key)` (palette accent and icon of the subject, `--subject`), `.subject-line`, `.subject-card`;
  `course/_summary` (`.progress-lines`) gives the three lines of a subject (mandatory topics done with a meter, optional ones done, the entry
  test in three words), on Materie, on Materia and, summed, on Oggi (D-326). A topic row has three looks by `data-status` (`topic_status_icon`).
- **«Ora» card** (`.now-card`): the single next thing on Oggi (entry test, then the topic left, then the first suggestion), one primary button.
- **Topic**: `ol.topic-steps` of two `.topic-step` cards (1 Lezione, 2 Esercizi) with a state pill each.
- **Practice**: the exercise is `.exercise-card`; `#feedback` becomes `.notice` with the outcome's tone (`success`, `nearly`, `error`, `info`);
  the skill state is a pill with three `.dots` (corrections without help, `skill.clean` in the payload); hints are a `.notice.hint`.
- **Sitting and warm-up**: question and answer in one `.sitting-card`; `.sticky-actions` keeps «Invia» and «Non lo so» on screen on a phone,
  above the MathLive keyboard (`--keyboard-offset`, set from its `geometrychange` in `items/expression.js`); «Come si risponde» is a `details.disclosure`.
- **End screen**: «non è un voto» first, only non-empty groups as `.result-group` cards (skills as `.tag-list`).

## The teacher's pages (D-308)

Styles: `app/assets/stylesheets/teacher.css` (page layouts only; the parts are the components above). Patterns used on every teacher page:

- **Shell:** `teacher/_menu` (bar; a "Menu" sheet on a phone), `teacher/_crumbs` (breadcrumb; on a phone the nearest parent as a back link) and the subject switcher. A page adds no back link of its own; a page without a breadcrumb passes `back:` to `ui_page_header`.
- **Decision card:** `section.approve.card.action` holds the one approve button, the other actions beside it and the reason it is off. An approved thing is a `ui_pill` in the header, the button stays in the card (off).
- **Stat strip and subject cards** (Cruscotto): `ul.stat-strip > li.stat`, `ul.cards.dash-subjects > li.subject.card` with `.cell-head` rows (icon, title link, `ui_pill`).
- **Findings:** `.finding` with `.finding-head` (a severity pill), `.finding-quote`, then the form with a visible label and a `.button-row`.
- **Folded data:** raw data and rare actions sit in `details.disclosure`; a step of a long page is `details.review-step.card` (open while not done).
- **Rows with pills:** `li.row` with `.row-main` and `.row-end` for lists of skills; a pill says the state in words.
- **Quote block:** `.answer-quote` for the student's words.
- **Actions menu:** `details.report-actions > details.action-row`, one row per action, each opens its own form (a danger button).
- The lesson's `.badge` is a square in a lesson; on a teacher page it is a rounded label (`body.teacher .badge`).

## The Italian translation of the english and spanish courses (D-402)

- **State machine:** `.tr[lang=it][data-nospeech]` shows when its nearest scope (`data-tr-scope` card, block, item or page) is open, or always for «Sempre visibile» and for the
  teacher's pages and the preview. «Traduzione» (`button.tr-toggle`) flips its scope; a small unit button on a long block flips that block. No translation button inside a control.
- **Lessons:** «Traduzione» is in the card head; every text has its Italian under it as a `.tr`, never read by «Ascolta»; a table cell has its Italian under it (`header_it`/`rows_it`);
  a figure has one translation panel under the drawing, from the figure's own `tr`; tiles, span chips and the `listen` text are target fragments with no translation of their own.
  The lesson review point count for a bilingual lesson is 13.
- **Practice:** a bilingual exercise is a scope: «Traduzione» sits beside «Controlla» and later moves to the next-actions row, so the solution stays readable in both. The Italian of a
  reading passage (the item's or the instance's own) reaches the page only with the solution or a closing reply (`passage_it`). Match-right options and ordering fragments under three
  words have no translation line. The skill name (page header) and the exercise list's skill names are a page scope with their own «Traduzione»; the closing screen names the next topic
  in the language it teaches, with its Italian and a «Traduzione» of its own. Oggi, the subject page, civics, the topic page and the schemas pages carry a page-scope button when a title is paired.
