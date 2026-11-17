---
name: lesson-physical-education
version: 1
formats: banco.lesson/2
---

# Brief: lessons of scienze motorie (`physical_education`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. The subject has no entry test and no blueprint: its content is the skill graph, the course map, the lessons and
the practice items, through the usual pipeline. The programme it follows is the official one (`ufficiale-2026-27`, the section «Scienze motorie e sportive»): the
seconda programme has no section for it, so every `taught_in` and `needed_by` ref is on the official source (`banco brief show course`, `banco brief show skill-graph`).

## What this subject is here

Theory and exercises only. The practical part (the gym, the tests, the workouts) stays outside the app: never a physical test, never a workout to perform, never a
count of repetitions or a timetable to follow. The student reads and answers questions on the page.

It is schematic and quick to read and do:

- Short cards, one idea per card, few words. A list, a small table or a labelled figure comes before a paragraph; a sentence of 15 words is already long.
- A card is a list, a table of 2 or 3 columns, a small schema or a short definition with one example, never a page of prose.
- Name a thing once and always with the same word (the same word for the same muscle, the same rule of the same sport): the exam asks for those words.
- The lesson stops well before its limits: 250 words are plenty. If a topic needs more, say it in the course map and split it in two topics.

School-level health facts only. Never medical advice: no diet, no menu, no calories to eat, no dose, no number that needs a doctor (heart rate zones, body mass, weights, doses of
a supplement). For health and first aid say what the school programme says: what the thing is, what it is for, when to call for help (112), never how to treat a person beyond the
basic gestures of the programme. Doping: what it is and why it is forbidden, no names of substances to take.

## Topics planned

Each is one or more topics of the course map; the skills are the things a student can do on the page.

1. **Apparato locomotore**: ossa (the main bones, flat, long and short bones), articolazioni (mobile, semimobile, fixed; the main movements), muscoli (the main ones by region, what a muscle does, contraction and tendons).
2. **Capacità motorie e allenamento**: capacità condizionali (forza, resistenza, velocità, mobilità articolare) and coordinative; why and how to warm up (riscaldamento), what the parts of a session are; never a programme of sessions.
3. **Sport di squadra: pallavolo e pallacanestro**: the rules (court, team, scoring, main faults) and the fundamental skills (the touches and the shots, the roles) of each.
4. **Atletica leggera**: corse, salti, lanci: the events of each group and what distinguishes them; the rules of the race and of the throw at school level.
5. **Salute e sport**: benefits of movement, alimentazione (the balanced plate in words, hydration, no diet), doping (what it is and why not), primo soccorso (the basic gestures in order: look, call 112, do not move the injured person without need).

## Practice items

For the practice items (`banco brief show practice-item`) use choice, matching of 4 rows or more, ordering and short written answers, so that a skill can be demonstrated: 3 right without help, at least 2 of them hard to guess.
A matching of bones to regions, of events to groups, of rules to sports; an ordering of the parts of a warm-up or of the gestures of first aid; a short written answer of one or two words for a name.
A choice alone is never enough for a skill. Write no item that asks the student to do an exercise or to report a result of a test: only to know, name, match and order.

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). They are the ones of the other subjects that fit, with their colour, icon and shape. The carrier says how a role is told apart without colour.

- `cause` (perché): icon, icon `milestone`, shape diamond, question "Perché?".
- `purpose` (a che serve): icon, icon `target`, shape box, question "A che cosa serve?".
- `time` (quando): icon, icon `clock`, shape ring, question "Quando si fa?".

Use a role only when it tells the student something (why a muscle works so, what a rule is for, when a phase comes); most cards need none.

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `name` (Dai il nome), icon `tag`.
- `classify` (Metti nel gruppo), icon `boxes`.
- `order` (Metti in ordine), icon `list-ordered`.
- `compare` (Confronta), icon `git-compare`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`dumbbell`, `heart-pulse`, `milestone`, `target`, `clock`, `tag`, `boxes`, `list-ordered`, `git-compare`.

## Types of this subject

The subject has no piece of its own, and no physics or chemistry piece applies to it. Use the generic ones, only if they are `available`:

| Piece | Kind | Use here |
|---|---|---|
| `table` | block and schema | a small table: bones by type, events by group, rules by sport |
| `concept_map` | schema | a classification (the capacità motorie, the athletics events) |
| `flow` | schema | an ordered sequence (the gestures of first aid, the parts of a warm-up) |
| `nested` | diagram | "is made of" (a muscle, a joint) |
| `chain` | diagram | a cause and its effects (movement and benefit) |

`banco lesson submit --dry-run` says what is not available.

## Rules of the subject

- Right and wrong are never colours: the correct answer is never green. The palette follows the other subjects.
- Facts are those of a school textbook of the biennio; if you are unsure of a fact (a measure of a court, a rule of a sport), leave it out or write it without the number.
- Rules of a sport change: write the rule as the school programme gives it, never the latest federation rule you remember, and no date or record.
- Names of people, teams, clubs and brands do not appear in a lesson; an example uses «una squadra» and «un atleta».
- No sentence tells the student to try a movement at home: a figure shows a position, the text names it.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
